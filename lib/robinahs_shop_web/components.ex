defmodule RobinahsShopWeb.Components do
  use Phoenix.Component

  @doc """
  Two-letter monogram used where a product has no photograph of its own.
  Products without a photo are never given another item's picture.
  """
  def photo_monogram(name) when is_binary(name) do
    name
    |> String.split(~r/\s+/, trim: true)
    |> Enum.take(2)
    |> Enum.map_join("", fn word ->
      word |> String.replace(~r/[^\p{L}\p{N}]/u, "") |> String.first() || ""
    end)
    |> String.upcase()
    |> case do
      "" -> "?"
      monogram -> monogram
    end
  end

  def photo_monogram(_), do: "?"
  def money(nil), do: money(0)

  def money(value) do
    formatted =
      value
      |> round()
      |> Integer.to_string()
      |> String.reverse()
      |> String.graphemes()
      |> Enum.chunk_every(3)
      |> Enum.map_join(",", &Enum.join/1)
      |> String.reverse()

    "UGX " <> formatted
  end

  def local_time(dt), do: dt |> DateTime.add(10_800) |> Calendar.strftime("%d %b %Y, %H:%M EAT")
  attr :name, :string, default: "arrow"
  attr :size, :integer, default: 18

  def icon(assigns) do
    path =
      case assigns.name do
        "bag" ->
          "M5 7h14l1 14H4L5 7 M8 7V6a4 4 0 0 1 8 0v1"

        "cart" ->
          "M2.05 2.05h2l2.66 12.42a2 2 0 0 0 2 1.58h9.78a2 2 0 0 0 1.95-1.57l1.65-7.43H5.12 M8 20a1 1 0 1 0 0 2a1 1 0 1 0 0-2 M19 20a1 1 0 1 0 0 2a1 1 0 1 0 0-2"

        "search" ->
          "M21 21l-5-5 M18 10a8 8 0 1 1-16 0 8 8 0 0 1 16 0"

        "pin" ->
          "M20 10c0 6-8 12-8 12S4 16 4 10a8 8 0 1 1 16 0 M15 10a3 3 0 1 1-6 0 3 3 0 0 1 6 0"

        "box" ->
          "M3 6l9-4 9 4v12l-9 4-9-4V6 M3 6l9 4 9-4 M12 10v12"

        "chat" ->
          "M21 11a9 9 0 0 1-9 9 10 10 0 0 1-4-1l-6 3 2-6a9 9 0 1 1 17-5"

        "lock" ->
          "M5 10h14v11H5V10 M8 10V6a4 4 0 0 1 8 0v4"

        "phone" ->
          "M5 2l4 5-3 3c2 4 4 6 8 8l3-3 5 4c-2 7-9 3-14-2S-1 4 5 2"

        "close" ->
          "M5 5l14 14 M19 5L5 19"

        "menu" ->
          "M3 5h18 M3 12h18 M3 19h18"

        "plus" ->
          "M12 4v16 M4 12h16"

        "check" ->
          "M20 6L9 17l-5-5"

        "refresh" ->
          "M23 4v6h-6 M1 20v-6h6 M3.51 9a9 9 0 0 1 14.85-3.36L23 10 M1 14l4.64 4.36A9 9 0 0 0 20.49 15"

        "download" ->
          "M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4 M7 10l5 5 5-5 M12 15V3"

        _ ->
          "M4 12h16 M14 6l6 6-6 6"
      end

    assigns = assign(assigns, :path, path)

    ~H"""
    <svg
      width={@size}
      height={@size}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="1.7"
      stroke-linecap="round"
      stroke-linejoin="round"
      aria-hidden="true"
    ><path d={@path} /></svg>
    """
  end

  @doc """
  Shared trolley trigger (cart/trolley icon + live count badge and total).
  Used by both the storefront and the POS so the basket is a single source of truth.
  """
  attr :count, :integer, required: true
  attr :total, :integer, default: nil
  attr :open, :boolean, default: false
  attr :label, :string, default: "Enquiry"
  attr :on_click, :string, required: true
  attr :class, :string, default: nil

  def trolley_button(assigns) do
    ~H"""
    <button
      type="button"
      class={["trolley-button", @class]}
      phx-click={@on_click}
      aria-label={"Toggle basket, #{@count} items"}
      aria-expanded={to_string(@open)}
    >
      <.icon name="cart" /><span>{@label}</span>
      <b :if={@count > 0}>{@count}</b>
      <small :if={@total && @total > 0} class="trolley-total">{money(@total)}</small>
    </button>
    """
  end

  @doc """
  Shared cart line item (name, unit price, quantity stepper, row total).
  `row_total` auto-increments as quantity changes.
  """
  attr :name, :string, required: true
  attr :unit_price, :integer, default: 0
  attr :unit, :string, default: nil
  attr :quantity, :integer, required: true
  attr :id, :string, required: true
  attr :on_plus, :string, required: true
  attr :on_minus, :string, required: true
  attr :on_remove, :string, default: nil

  def cart_line(assigns) do
    assigns =
      assign(assigns, :row_total, assigns.unit_price * assigns.quantity)

    ~H"""
    <div class="cart-line">
      <div class="cart-line-info">
        <b>{@name}</b>
        <small>
          {if @unit_price > 0,
            do: money(@unit_price) <> if(@unit, do: " / " <> @unit, else: ""),
            else: "Confirm price"}
        </small>
      </div>
      <div class="quantity cart-line-qty">
        <button
          type="button"
          phx-click={@on_minus}
          phx-value-id={@id}
          aria-label={"Decrease #{@name}"}
        >
          −
        </button>
        <span class="qty-value">{@quantity}</span>
        <button type="button" phx-click={@on_plus} phx-value-id={@id} aria-label={"Increase #{@name}"}>
          +
        </button>
      </div>
      <b class="cart-line-total">{if @unit_price > 0, do: money(@row_total), else: "—"}</b>
      <button
        :if={@on_remove}
        type="button"
        class="cart-line-remove"
        phx-click={@on_remove}
        phx-value-id={@id}
        aria-label={"Remove #{@name}"}
      ><.icon name="close" size={16} /></button>
    </div>
    """
  end

  @doc """
  Verified stock state badge built from database values only.
  """
  attr :product, :map, required: true

  def stock_badge(assigns) do
    {class, label} =
      case RobinahsShop.Shop.stock_status(assigns.product) do
        :out_of_stock ->
          {"out", "Out of stock"}

        :low_stock ->
          {"low", "Low stock · #{assigns.product.stock} #{assigns.product.unit}"}

        :available ->
          {"ok", "Available · #{assigns.product.stock} #{assigns.product.unit}"}
      end

    assigns = assign(assigns, class: class, label: label)

    ~H"""
    <span class={"stock-state " <> @class}>{@label}</span>
    """
  end
end
