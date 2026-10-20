defmodule RobinahsShop.Shop do
  import Ecto.Query
  alias RobinahsShop.{Repo, Accounts, Catalogue, Product, Sale, SaleItem, Receiving, Expense}

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

  @doc """
  Operating expenses are recorded manually by the owner or a manager. Like
  sales, they are whole UGX amounts and never fractional.
  """
  def expense_categories, do: Expense.categories()

  def change_expense(expense \\ %Expense{}, attrs \\ %{}), do: Expense.changeset(expense, attrs)

  def record_expense(actor, attrs) do
    if Accounts.allowed?(actor, :expense) do
      result =
        %Expense{staff_id: actor.id}
        |> Expense.changeset(attrs)
        |> Repo.insert()

      announce(result)
    else
      {:error, :forbidden}
    end
  end

  def recent_expenses(actor, limit \\ 50) do
    if Accounts.allowed?(actor, :expense) do
      Repo.all(from e in Expense, order_by: [desc: e.spent_on, desc: e.id], limit: ^limit)
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

      revenue = total || 0
      cogs = cost_of_goods_sold(query)
      expenses = operating_expenses(filters)
      gross_profit = revenue - cogs
      net_profit = gross_profit - expenses

      {:ok,
       %{
         total: revenue,
         count: count,
         average: if(count > 0, do: div(revenue, count), else: 0),
         methods: methods,
         best: best,
         sales: sales,
         cogs: cogs,
         gross_profit: gross_profit,
         expenses: expenses,
         net_profit: net_profit
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

  @doc false
  # Cost of goods sold for the sales matched by `sales_query/1`. The buying
  # cost of each unit is the average across that product's recorded deliveries
  # (total buying cost divided by total received quantity); a product with no
  # recorded buying cost contributes nothing rather than inventing a figure.
  defp cost_of_goods_sold(query) do
    from(i in SaleItem,
      join: s in subquery(query),
      on: i.sale_id == s.id,
      group_by: i.product_id,
      select: {i.product_id, sum(i.quantity)}
    )
    |> Repo.all()
    |> Enum.reduce(0, fn {product_id, quantity}, acc ->
      acc + average_unit_cost(product_id) * quantity
    end)
  end

  defp average_unit_cost(product_id) do
    {cost, quantity} =
      Repo.one(
        from(r in Receiving,
          where: r.product_id == ^product_id and not is_nil(r.buying_cost),
          select: {sum(r.buying_cost * r.quantity), sum(r.quantity)}
        )
      )

    if quantity && quantity > 0, do: div(cost, quantity), else: 0
  end

  @doc false
  # Expenses carry a plain calendar date, so the range is compared against the
  # same filter dates directly rather than the EAT-midnight instants used for
  # sale timestamps.
  defp operating_expenses(filters) do
    with {:ok, first} <- expense_date(filters["from"]),
         {:ok, last} <- expense_date(filters["to"]) do
      query = from(e in Expense)
      query = if first, do: from(e in query, where: e.spent_on >= ^first), else: query
      query = if last, do: from(e in query, where: e.spent_on <= ^last), else: query

      Repo.one(from(e in query, select: coalesce(sum(e.amount), 0)))
    else
      _ -> 0
    end
  end

  defp expense_date(value) when value in [nil, ""], do: {:ok, nil}

  defp expense_date(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> {:ok, date}
      _ -> {:error, :invalid_dates}
    end
  end

  @doc """
  A small starter ledger so the profit report has something to show on a fresh
  deployment. Idempotent: it does nothing once any expense exists, and it only
  runs when an owner account is present to attribute the entries to.
  """
  def seed_expenses do
    owner = Repo.one(from s in RobinahsShop.Staff, where: s.role == :owner, limit: 1)

    if owner && not Repo.exists?(Expense) do
      today = Date.utc_today()

      [
        {"Rent", "Monthly shop rent", 300_000, 0},
        {"Utilities", "Umeme electricity token", 45_000, 2},
        {"Transport", "Boda delivery of stock", 18_000, 3},
        {"Packaging", "Carrier bags and wrap", 12_000, 5}
      ]
      |> Enum.each(fn {category, description, amount, days_ago} ->
        Repo.insert!(%Expense{
          staff_id: owner.id,
          spent_on: Date.add(today, -days_ago),
          category: category,
          description: description,
          amount: amount
        })
      end)
    end
  end

  # A simple deterministic price table so seeded items can be used for
  # end-to-end tests and a sensible till without requiring manual review.
  @mock_prices %{
    1 => 5_000,
    2 => 3_000,
    3 => 8_000,
    4 => 25_000,
    5 => 5_000,
    6 => 12_000,
    7 => 1_000,
    8 => 2_000,
    9 => 6_000,
    10 => 350_000,
    11 => 15_000,
    12 => 3_000,
    13 => 45_000,
    14 => 280_000,
    15 => 18_000,
    16 => 4_000,
    17 => 6_000,
    18 => 8_000,
    19 => 1_000,
    20 => 12_000,
    21 => 10_000,
    22 => 7_000,
    23 => 16_000,
    24 => 12_000,
    25 => 2_000,
    26 => 2_000,
    27 => 7_000,
    28 => 3_000,
    29 => 1_000,
    30 => 5_000,
    31 => 9_000,
    32 => 8_000,
    33 => 6_000,
    34 => 2_000,
    35 => 9_000,
    36 => 10_000
  }

  def mock_price(number), do: Map.get(@mock_prices, number, 5_000)

  def seed_catalogue do
    Enum.each(Catalogue.items(), fn {number, name, category, unit, image} ->
      sku = Catalogue.sku(number)

      case Repo.get_by(Product, sku: sku) do
        nil ->
          Repo.insert!(
            Product.changeset(%Product{}, %{
              sku: sku,
              name: name,
              category: category,
              unit: unit,
              image: resource_image(image),
              price: mock_price(number)
            })
          )

          # Give every seeded catalogue item a starting stock of 10 pieces.
          Repo.update_all(from(p in Product, where: p.sku == ^sku), set: [stock: 10])

        product ->
          # The catalogue photograph is the single source of truth for a
          # row's picture. A missing photo or an inherited category
          # placeholder is upgraded; a manager's own item photo is never
          # overwritten.
          if placeholder_image?(product.image) do
            product |> Ecto.Changeset.change(image: resource_image(image)) |> Repo.update!()
          else
            :ok
          end

          # Ensure seeded catalogue items have 10 in stock and a mock unit price
          # when price hasn't been explicitly confirmed.
          if product.price == 0 do
            product |> Ecto.Changeset.change(price: mock_price(number), stock: max(product.stock, 10)) |> Repo.update!()
          else
            product |> Ecto.Changeset.change(stock: max(product.stock, 10)) |> Repo.update!()
          end
      end
    end)

    # Retire the old placeholder rows: their category photos already illustrate
    # the collection tiles, so keeping them would show the same picture twice.
    Repo.update_all(
      from(p in Product, where: fragment("upper(?) LIKE 'DEMO-%'", p.sku)),
      set: [active: false, updated_at: DateTime.utc_now()]
    )

    retire_note_duplicates()
  end

  # Earlier deployments created extra rows from the same note using a shared
  # category photo, so one placeholder picture appeared on many cards. Rows
  # outside the catalogue that repeat a note row's name while still carrying a
  # shared placeholder photo are retired after their live stock and confirmed
  # selling price are moved onto the catalogue row, so consolidating onto the
  # catalogue never loses the shop's working data.
  defp retire_note_duplicates do
    note_names = Enum.map(Catalogue.items(), fn {_, name, _, _, _} -> normalize_name(name) end)

    from(p in Product, where: p.active and not like(p.sku, "RSH-%"))
    |> Repo.all()
    |> Enum.filter(fn product ->
      placeholder_image?(product.image) and
        duplicates_note?(normalize_name(product.name), note_names)
    end)
    |> Enum.each(fn product ->
      migrate_legacy_row(product)
      product |> Ecto.Changeset.change(active: false) |> Repo.update!()
    end)
  end

  defp migrate_legacy_row(legacy) do
    with {:ok, number} <- unique_note_match(legacy.name),
         %Product{} = row <- Repo.get_by(Product, sku: Catalogue.sku(number)) do
      row
      |> Ecto.Changeset.change(
        stock: row.stock + legacy.stock,
        price: if(row.price > 0, do: row.price, else: legacy.price)
      )
      |> Repo.update!()
    else
      _ -> :ok
    end
  end

  defp unique_note_match(name) do
    normalized = normalize_name(name)

    case Enum.filter(Catalogue.items(), fn {_, note, _, _, _} ->
           duplicates_note?(normalized, [normalize_name(note)])
         end) do
      [{number, _, _, _, _}] -> {:ok, number}
      _ -> :error
    end
  end

  defp duplicates_note?(name, note_names) do
    Enum.any?(note_names, fn note ->
      cond do
        note == name -> true
        byte_size(name) >= 8 -> String.starts_with?(note, name) or String.starts_with?(name, note)
        true -> false
      end
    end)
  end

  defp normalize_name(name) do
    name |> String.downcase() |> String.replace(~r/[^a-z0-9]+/, " ") |> String.trim()
  end

  defp placeholder_images do
    # Placeholder photos are the category pictures used by the collection
    # tiles; they are never a product's own photograph.
    Enum.map(
      ~w(kitchen-essentials.jpg travel-everyday-bags.jpg bedding-comfort.jpg household-storage.jpg school-essentials.jpg home-organisation.jpg),
      &"/resources/#{&1}"
    )
  end

  defp placeholder_image?(nil), do: true
  defp placeholder_image?(image), do: image in placeholder_images()

  defp resource_image(nil), do: nil

  defp resource_image(file) do
    path = Path.join([:code.priv_dir(:robinahs_shop), "static", "resources", file])
    if File.exists?(path), do: "/resources/" <> file, else: nil
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
