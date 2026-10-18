defmodule RobinahsShop.StockList do
  @moduledoc """
  Review workflow for the handwritten stock document.

  The document records listed quantities and amounts as written. Neither
  establishes verified available stock nor selling unit prices, and listed
  amounts must never be divided by quantities to infer prices. Entries stay
  pending until a manager links a real product and types a confirmed unit
  price; only then is the linked product's selling price updated.
  """

  import Ecto.Query
  alias RobinahsShop.{Repo, Accounts, Product, Shop, StockListEntry}

  @source_note "Transcribed from the handwritten note. Some unclear words are flagged for checking."

  @reference_rows [
    {1, "Cup with numbers", "1", "1,000", false, false},
    {2, "Toilet paper", "4", "2,000", false, false},
    {3, "Colgate Herbal (M)", "2", "8,000", false, false},
    {4, "Nomi buckets", "2", "8,000", false, false},
    {5, "Dry cell", "1 pair", "2,000", false, false},
    {6, "Torch", "1", "2,000", false, false},
    {7, "Lato milk sachets", "2", "1,000", false, false},
    {8, "Ruler", "1", "1,000", false, false},
    {9, "Black book (1½ Quire)", "2", "8,000", false, false},
    {10, "Mattress Rose Foam (4*6) tape edge", "1", "165,000", false, false},
    {11, "Butto (1 litre)", "1", "9,000", false, false},
    {12, "Bay… (lb; item name unclear)", "1", "1,000", true, false},
    {13, "Bed sheets plain White (Sunbelt)", "3", "45000", false, false},
    {14, "Mattress ecofoam 4 inch", "1", "85000", false, false},
    {15, "Baby patra", "1", "2,500", false, false},
    {16, "Rice (half kg)", "1", "2,000", false, false},
    {17, "Baby knicker", "4", "4,000", false, false},
    {18, "Butto (half litre)", "1", "4,500", false, false},
    {19, "Hand ker chief", "1", "2,000", false, false},
    {20, "Steel bottle (Medium)", "2", "20,000", false, false},
    {21, "Relax bottle", "1", "10,000", false, false},
    {22, "Vest (b)", "1", "5,000", false, false},
    {23, "Half pot (big)", "1", "4,000", false, false},
    {24, "Set mathematical", "1", "3,000", false, false},
    {25, "Blue soap", "3 bars", "10,500", false, false},
    {26, "Ruler", "1", "1,000", false, false},
    {27, "Shoe polish (Kangaroo)", "1", "2,000", false, false},
    {28, "Shoe brush", "1", "1,000", false, false},
    {29, "Rubber", "1", "1,000", false, false},
    {30, "Geisha (small)", "1", "3,000", false, false},
    {31, "Go-back stocks", "2", "5,000", true, false},
    {32, "Breakable bowl / plate", "1", "3,000", false, false},
    {33, "Angel cup (s)", "2", "1,000", false, false},
    {34, "Sponge", "1", "1,500", false, false},
    {35, "Colgate charcoal (b)", "1", "8000", false, false},
    {36, "Vaseline (b)", "1", "1,0000", false, true}
  ]

  @ruler_note "Two Ruler entries are recorded (08 and 26); their relationship is not yet confirmed."
  @bay_note "Item name copied as written; confirm the real product against the original note."
  @go_back_note "Grouped return-stock line; confirm which products this covers."
  @vaseline_note "Amount copied literally as written ('1,0000'); confirm the intended figure."

  @filters ~w(all review confirmed)
  @max_price 1_000_000_000

  def source_note, do: @source_note
  def per_page, do: 9
  def reference_count, do: length(@reference_rows)
  def filters, do: @filters

  @doc """
  Inserts any reference rows that are still missing. Already recorded rows,
  including reviewed ones, are never modified.
  """
  def ensure_reference! do
    present = Repo.all(from e in StockListEntry, select: e.number) |> MapSet.new()

    @reference_rows
    |> Enum.reject(fn {number, _, _, _, _, _} -> MapSet.member?(present, number) end)
    |> Enum.each(fn {number, item, quantity, amount, name_flag, amount_flag} ->
      %StockListEntry{}
      |> Ecto.Changeset.change(%{
        number: number,
        item: item,
        quantity_as_listed: quantity,
        amount_as_written: amount,
        needs_name_review: name_flag,
        needs_amount_review: amount_flag,
        notes: note_for(number),
        status: :pending
      })
      |> Repo.insert!()
    end)

    :ok
  end

  defp note_for(8), do: @ruler_note
  defp note_for(26), do: @ruler_note
  defp note_for(12), do: @bay_note
  defp note_for(31), do: @go_back_note
  defp note_for(36), do: @vaseline_note
  defp note_for(_), do: nil

  @doc """
  Returns the matching reference entries for one page plus accurate counts.
  """
  def list_entries(params \\ %{}) when is_map(params) do
    filter = normalize_filter(Map.get(params, "filter"))
    searched = search_query(base_query(), normalize_search(Map.get(params, "q")))

    review_required =
      Repo.aggregate(from(e in searched, where: e.status == :pending), :count)

    query = status_query(searched, filter)
    total = Repo.aggregate(query, :count)

    page = params |> Map.get("page", 1) |> page_number()
    pages = pages(total, per_page())
    page = min(page, pages)
    offset = (page - 1) * per_page()

    entries =
      query
      |> limit(^per_page())
      |> offset(^offset)
      |> Repo.all()

    first = if total == 0, do: 0, else: offset + 1
    last = min(offset + per_page(), total)

    %{
      entries: entries,
      total: total,
      page: page,
      pages: pages,
      per_page: per_page(),
      first: first,
      last: last,
      filter: filter,
      review_required: review_required
    }
  end

  defp base_query, do: from(e in StockListEntry, preload: [:product], order_by: [asc: e.number])

  defp search_query(query, ""), do: query

  defp search_query(query, term) do
    like = "%" <> term <> "%"

    from(e in query,
      where:
        fragment("lower(?) LIKE ?", e.item, ^like) or
          fragment("CAST(? AS TEXT) LIKE ?", e.number, ^like)
    )
  end

  defp status_query(query, "review") do
    from(e in query, where: e.status == :pending or e.needs_name_review or e.needs_amount_review)
  end

  defp status_query(query, "confirmed"), do: from(e in query, where: e.status == :confirmed)
  defp status_query(query, _), do: query

  defp normalize_search(value) when is_binary(value),
    do: value |> String.trim() |> String.downcase()

  defp normalize_search(_), do: ""

  defp normalize_filter(value) when value in @filters, do: value
  defp normalize_filter(_), do: "all"

  defp page_number(value) when is_integer(value) and value > 0, do: value

  defp page_number(value) when is_binary(value) do
    case Integer.parse(value) do
      {number, ""} when number > 0 -> number
      _ -> 1
    end
  end

  defp page_number(_), do: 1

  defp pages(0, _), do: 1
  defp pages(total, size), do: (total + size - 1) |> div(size)

  @doc """
  Page numbers to render around the current page, with `:gap` markers.
  """
  def page_window(_page, pages) when pages <= 7, do: Enum.to_list(1..pages//1)

  def page_window(page, pages) do
    middle = Enum.to_list(max(1, page - 1)..min(pages, page + 1)//1)

    leading = if hd(middle) > 1, do: [1, :gap], else: []
    trailing = if List.last(middle) < pages, do: [:gap, pages], else: []

    leading ++ middle ++ trailing
  end

  @doc """
  Records a confirmed unit price for a reference entry. A linked product's
  selling price is updated to the confirmed value inside the same transaction.
  """
  def confirm_entry(actor, entry_id, params) when is_map(params) do
    with true <- Accounts.allowed?(actor, :manage),
         %StockListEntry{} = entry <- Repo.get(StockListEntry, entry_id),
         {:ok, price} <- unit_price(params["confirmed_unit_price"]),
         {:ok, product_id} <- link_product(params["product_id"]) do
      now = DateTime.utc_now()

      Repo.transaction(fn ->
        entry =
          entry
          |> StockListEntry.review_changeset(%{
            status: :confirmed,
            confirmed_unit_price: price,
            confirmed_at: now,
            confirmed_by_staff_id: actor.id,
            product_id: product_id
          })
          |> Repo.update!()

        if product_id do
          product = Repo.get(Product, product_id)

          if product do
            product
            |> Ecto.Changeset.change(price: price)
            |> Repo.update!()

            notify_shop_change()
          end
        end

        entry
      end)
    else
      false -> {:error, :forbidden}
      nil -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  def confirm_entry(_, _, _), do: {:error, :forbidden}

  @doc """
  Reference rows as CSV. Listed amounts stay exactly as written and are never
  presented as unit prices or verified stock.
  """
  def export_csv(actor) do
    if Accounts.allowed?(actor, :receive) do
      entries = Repo.all(base_query())

      rows = [
        [
          "number",
          "item",
          "quantity_as_listed",
          "amount_ugx_as_written",
          "unit_price_status",
          "confirmed_unit_price",
          "linked_product",
          "available_stock_status",
          "review_notes",
          "entry_status"
        ]
        | Enum.map(entries, fn entry ->
            [
              entry.number,
              entry.item,
              entry.quantity_as_listed,
              entry.amount_as_written,
              unit_price_status(entry),
              entry.confirmed_unit_price || "",
              linked_product(entry),
              availability_status(entry),
              entry.notes || "",
              entry.status
            ]
          end)
      ]

      {:ok,
       Enum.map_join(rows, "\r\n", fn row -> Enum.map_join(row, ",", &csv_cell/1) end) <> "\r\n"}
    else
      {:error, :forbidden}
    end
  end

  def unit_price_status(%StockListEntry{status: :confirmed, confirmed_unit_price: price})
      when is_integer(price),
      do: "Confirmed"

  def unit_price_status(_), do: "Confirm"

  def availability_status(%StockListEntry{product: %Product{} = product}),
    do: product |> Shop.stock_status() |> status_label()

  def availability_status(_), do: "Not linked to a product"

  defp status_label(:out_of_stock), do: "Out of stock"
  defp status_label(:low_stock), do: "Low stock"
  defp status_label(:available), do: "Available"

  defp linked_product(%StockListEntry{product: %Product{} = product}),
    do: "#{product.sku} · #{product.name}"

  defp linked_product(_), do: ""

  defp unit_price(nil), do: {:error, :price_required}

  defp unit_price(value) when is_binary(value) do
    case String.trim(value) do
      "" ->
        {:error, :price_required}

      number ->
        case Integer.parse(number) do
          {parsed, ""} -> unit_price(parsed)
          _ -> {:error, :invalid_input}
        end
    end
  end

  defp unit_price(value) when is_integer(value) do
    if value >= 0 and value <= @max_price, do: {:ok, value}, else: {:error, :invalid_input}
  end

  defp unit_price(_), do: {:error, :invalid_input}

  defp link_product(value) when value in [nil, ""], do: {:ok, nil}

  defp link_product(value) when is_integer(value) and value > 0, do: {:ok, value}

  defp link_product(value) when is_binary(value) and byte_size(value) <= 12 do
    case Integer.parse(value) do
      {number, ""} when number > 0 -> {:ok, number}
      _ -> {:error, :invalid_input}
    end
  end

  defp link_product(_), do: {:error, :invalid_input}

  defp csv_cell(value) do
    value = to_string(value)
    value = if String.match?(value, ~r/^[=+@\-\t\r]/), do: "'" <> value, else: value
    "\"" <> String.replace(value, "\"", "\"\"") <> "\""
  end

  defp notify_shop_change,
    do: Phoenix.PubSub.broadcast(RobinahsShop.PubSub, "shop:changes", :shop_changed)
end
