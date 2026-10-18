defmodule RobinahsShop.Shop do
  import Ecto.Query
  alias RobinahsShop.{Repo, Accounts, Product, Sale, SaleItem, Receiving}

  @categories [
    "Home & Kitchen",
    "Bags & Travel",
    "Bedding & Comfort",
    "Household Plastics & Storage",
    "School Essentials"
  ]
  @methods ["Cash", "Manual mobile money record", "Card (manual record)"]
  def categories, do: @categories
  def payment_methods, do: @methods

  @doc """
  Verified stock state from database values. A product is low on stock when it
  is at or below its configured reorder level; no threshold is invented here.
  """
  def stock_status(%{stock: 0}), do: :out_of_stock

  def stock_status(%{stock: stock, reorder_level: level})
      when is_integer(level) and stock <= level,
      do: :low_stock

  def stock_status(%{stock: _}), do: :available

  def subscribe, do: Phoenix.PubSub.subscribe(RobinahsShop.PubSub, "shop:changes")
  def products, do: Repo.all(from p in Product, where: p.active == true, order_by: p.id)

  def all_products(actor),
    do:
      if(Accounts.allowed?(actor, :manage),
        do: Repo.all(from p in Product, order_by: p.id),
        else: products()
      )

  def change_product(product \\ %Product{}, attrs \\ %{}), do: Product.changeset(product, attrs)

  def save_product(actor, id, attrs) do
    if Accounts.allowed?(actor, :manage) do
      product = if id in [nil, ""], do: %Product{}, else: Repo.get(Product, id)

      if product do
        result = product |> Product.changeset(attrs) |> Repo.insert_or_update()
        announce(result)
      else
        {:error, :not_found}
      end
    else
      {:error, :forbidden}
    end
  end

  def receive(actor, attrs) do
    with true <- Accounts.allowed?(actor, :receive),
         {:ok, request} <- Ecto.UUID.cast(attrs["request_id"]),
         quantity when is_integer(quantity) and quantity > 0 and quantity <= 100_000 <-
           integer(attrs["quantity"]),
         product_id when is_integer(product_id) and product_id > 0 <- integer(attrs["product_id"]),
         cost when is_nil(cost) or (is_integer(cost) and cost >= 0 and cost <= 1_000_000_000) <-
           optional_integer(attrs["buying_cost"]),
         supplier when byte_size(supplier) <= 200 <- String.trim(attrs["supplier"] || ""),
         reference when byte_size(reference) <= 200 <- String.trim(attrs["reference"] || "") do
      fingerprint = fingerprint({actor.id, product_id, quantity, cost, supplier, reference})

      Repo.transaction(fn ->
        case Repo.get_by(Receiving, request_id: request) do
          nil ->
            product = Repo.get(Product, product_id)
            if is_nil(product) or not product.active, do: Repo.rollback(:not_found)
            if product.stock + quantity > 1_000_000_000, do: Repo.rollback(:invalid_input)

            Repo.update_all(from(p in Product, where: p.id == ^product_id),
              inc: [stock: quantity],
              set: [updated_at: DateTime.utc_now()]
            )

            Repo.insert!(%Receiving{
              request_id: request,
              fingerprint: fingerprint,
              staff_id: actor.id,
              product_id: product_id,
              quantity: quantity,
              buying_cost: cost,
              supplier: supplier,
              reference: reference
            })

          existing ->
            replay(existing, fingerprint)
        end
      end)
      |> announce()
    else
      false -> {:error, :forbidden}
      _ -> {:error, :invalid_input}
    end
  end

  def post_sale(actor, attrs) do
    with true <- Accounts.allowed?(actor, :sale),
         {:ok, request} <- Ecto.UUID.cast(attrs["request_id"]),
         method when method in @methods <- attrs["payment_method"],
         {:ok, items} <- normalize_items(attrs["items"]),
         cash when is_nil(cash) or (is_integer(cash) and cash >= 0 and cash <= 1_000_000_000_000) <-
           optional_integer(attrs["cash_received"]) do
      fingerprint = fingerprint({actor.id, items, method, cash})

      Repo.transaction(fn ->
        case Repo.get_by(Sale, request_id: request) do
          nil ->
            lines =
              Enum.map(items, fn {id, quantity} ->
                product = Repo.get(Product, id)
                if is_nil(product) or not product.active, do: Repo.rollback(:not_found)
                if product.price <= 0, do: Repo.rollback(:price_unset)

                {changed, _} =
                  Repo.update_all(
                    from(p in Product, where: p.id == ^id and p.stock >= ^quantity),
                    inc: [stock: -quantity],
                    set: [updated_at: DateTime.utc_now()]
                  )

                if changed != 1, do: Repo.rollback(:insufficient_stock)

                %{
                  product_id: id,
                  sku: product.sku,
                  name: product.name,
                  quantity: quantity,
                  unit_price: product.price
                }
              end)

            total =
              Enum.reduce(lines, 0, fn line, acc -> acc + line.quantity * line.unit_price end)

            if method == "Cash" and (is_nil(cash) or cash < total),
              do: Repo.rollback(:insufficient_cash)

            sale =
              Repo.insert!(%Sale{
                request_id: request,
                fingerprint: fingerprint,
                staff_id: actor.id,
                total: total,
                payment_method: method,
                cash_received: if(method == "Cash", do: cash),
                change: if(method == "Cash", do: cash - total)
              })

            Enum.each(lines, fn line ->
              Repo.insert!(struct(SaleItem, Map.put(line, :sale_id, sale.id)))
            end)

            Repo.preload(sale, :items)

          existing ->
            replay(existing, fingerprint) |> Repo.preload(:items)
        end
      end)
      |> announce()
    else
      false -> {:error, :forbidden}
      _ -> {:error, :invalid_input}
    end
  end

  defp normalize_items(items) when is_list(items) and length(items) in 1..100 do
    parsed =
      Enum.map(items, fn
        item when is_map(item) -> {integer(item["product_id"]), integer(item["quantity"])}
        _ -> {:invalid, :invalid}
      end)

    if Enum.all?(parsed, fn {id, qty} ->
         is_integer(id) and id > 0 and is_integer(qty) and qty in 1..100_000
       end) do
      combined =
        parsed
        |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
        |> Enum.map(fn {id, qs} -> {id, Enum.sum(qs)} end)
        |> Enum.sort()

      if Enum.all?(combined, fn {_, q} -> q <= 100_000 end),
        do: {:ok, combined},
        else: {:error, :invalid_input}
    else
      {:error, :invalid_input}
    end
  end

  defp normalize_items(_), do: {:error, :invalid_input}
  def integer(value) when is_integer(value), do: value

  def integer(value) when is_binary(value) and byte_size(value) <= 20 do
    case Integer.parse(value) do
      {n, ""} -> n
      _ -> :invalid
    end
  end

  def integer(_), do: :invalid
  defp optional_integer(v) when v in [nil, ""], do: nil
  defp optional_integer(v), do: integer(v)

  defp fingerprint(value),
    do: :crypto.hash(:sha256, :erlang.term_to_binary(value)) |> Base.encode16(case: :lower)

  defp replay(%{fingerprint: hash} = existing, hash), do: existing
  defp replay(_, _), do: Repo.rollback(:request_reused)

  defp announce({:ok, _} = result) do
    Phoenix.PubSub.broadcast(RobinahsShop.PubSub, "shop:changes", :shop_changed)
    result
  end

  defp announce(result), do: result

  def recent_sales(actor) do
    if Accounts.allowed?(actor, :sale) or Accounts.allowed?(actor, :report) do
      Repo.all(from s in Sale, order_by: [desc: s.id], limit: 10, preload: [:items])
    else
      []
    end
  end

  def recent_receivings(actor) do
    if Accounts.allowed?(actor, :receive) do
      Repo.all(from r in Receiving, order_by: [desc: r.id], limit: 30, preload: [:product])
    else
      []
    end
  end

  def report(actor, filters \\ %{}) do
    with true <- Accounts.allowed?(actor, :report), {:ok, query} <- sales_query(filters) do
      {total, count} = Repo.one(from s in query, select: {sum(s.total), count(s.id)})

      methods =
        Repo.all(
          from s in query,
            group_by: s.payment_method,
            select: %{method: s.payment_method, count: count(s.id), total: sum(s.total)}
        )

      best =
        Repo.all(
          from i in SaleItem,
            join: s in subquery(query),
            on: i.sale_id == s.id,
            group_by: [i.sku, i.name],
            order_by: [desc: sum(i.quantity)],
            limit: 10,
            select: %{
              name: i.name,
              sku: i.sku,
              quantity: sum(i.quantity),
              revenue: sum(i.quantity * i.unit_price)
            }
        )

      sales = Repo.all(from s in query, order_by: [desc: s.id], limit: 50, preload: [:items])

      {:ok,
       %{
         total: total || 0,
         count: count,
         average: if(count > 0, do: div(total, count), else: 0),
         methods: methods,
         best: best,
         sales: sales
       }}
    else
      false -> {:error, :forbidden}
      error -> error
    end
  end

  def export_csv(actor, filters) do
    with true <- Accounts.allowed?(actor, :report), {:ok, query} <- sales_query(filters) do
      rows = Repo.all(from s in query, order_by: [asc: s.id], preload: [:items])

      csv = [
        ["Sale ID", "Date UTC", "Payment method", "Payment status", "Total UGX", "Items"]
        | Enum.map(rows, fn s ->
            [
              "RS-#{s.id}",
              DateTime.to_iso8601(s.inserted_at),
              s.payment_method,
              "Manual record",
              s.total,
              Enum.map_join(s.items, "; ", fn i -> "#{i.name} x#{i.quantity}" end)
            ]
          end)
      ]

      {:ok,
       Enum.map_join(csv, "\r\n", fn row -> Enum.map_join(row, ",", &csv_cell/1) end) <> "\r\n"}
    else
      false -> {:error, :forbidden}
      error -> error
    end
  end

  defp csv_cell(value) do
    value = to_string(value)
    value = if String.match?(value, ~r/^[=+@\-\t\r]/), do: "'" <> value, else: value
    "\"" <> String.replace(value, "\"", "\"\"") <> "\""
  end

  defp sales_query(filters) do
    with {:ok, first} <- date_bound(filters["from"], 0),
         {:ok, last} <- date_bound(filters["to"], 1) do
      if first && last && DateTime.compare(first, last) != :lt do
        {:error, :invalid_dates}
      else
        query = from(s in Sale)
        query = if first, do: from(s in query, where: s.inserted_at >= ^first), else: query
        query = if last, do: from(s in query, where: s.inserted_at < ^last), else: query
        {:ok, query}
      end
    end
  end

  defp date_bound(value, _) when value in [nil, ""], do: {:ok, nil}

  defp date_bound(value, add_days) do
    case Date.from_iso8601(value) do
      {:ok, date} ->
        {:ok,
         date
         |> Date.add(add_days)
         |> DateTime.new!(~T[00:00:00], "Etc/UTC")
         |> DateTime.add(-10_800)}

      _ ->
        {:error, :invalid_dates}
    end
  end

  def seed_catalogue do
    items = [
      {"DEMO-KIT-001", "Everyday kitchen essentials", "Home & Kitchen", "kitchen-essentials.jpg",
       "set"},
      {"DEMO-BAG-001", "Travel and everyday bags", "Bags & Travel", "travel-everyday-bags.jpg",
       "piece"},
      {"DEMO-BED-001", "Bedding and comfort", "Bedding & Comfort", "bedding-comfort.jpg", "set"},
      {"DEMO-HOM-001", "Storage and household basics", "Household Plastics & Storage",
       "household-storage.jpg", "piece"},
      {"DEMO-SCH-001", "School essentials", "School Essentials", "school-essentials.jpg",
       "piece"},
      {"DEMO-ORG-001", "Home organisation", "Household Plastics & Storage",
       "home-organisation.jpg", "piece"}
    ]

    Enum.each(items, fn {sku, name, category, image, unit} ->
      unless Repo.get_by(Product, sku: sku),
        do:
          Repo.insert!(
            Product.changeset(%Product{}, %{
              sku: sku,
              name: name,
              category: category,
              image: "/resources/" <> image,
              unit: unit,
              price: 0
            })
          )
    end)
  end

  def error_message(%Ecto.Changeset{} = cs) do
    cs
    |> Ecto.Changeset.traverse_errors(fn {message, opts} ->
      Enum.reduce(opts, message, fn {key, v}, acc ->
        String.replace(acc, "%{#{key}}", to_string(v))
      end)
    end)
    |> Enum.map_join("; ", fn {field, errors} -> "#{field} #{Enum.join(errors, ", ")}" end)
  end

  def error_message(reason) do
    Map.get(
      %{
        forbidden: "Your staff role does not permit this action.",
        invalid_input: "Check the product, quantity and whole-UGX amounts.",
        not_found: "This product is unavailable.",
        price_unset: "Set a positive selling price before posting a sale.",
        insufficient_stock: "Insufficient stock. No sale was posted.",
        insufficient_cash: "Cash received must cover the sale total.",
        request_reused:
          "This request was already used for different details. Refresh and check history.",
        invalid_dates: "Enter a valid date range."
      },
      reason,
      "The operation could not be confirmed. Check history before retrying."
    )
  end
end
