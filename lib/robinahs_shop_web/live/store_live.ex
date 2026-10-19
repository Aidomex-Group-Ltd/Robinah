defmodule RobinahsShopWeb.StoreLive do
  use RobinahsShopWeb, :live_view

  def mount(_, _, socket) do
    if connected?(socket), do: Shop.subscribe()

    {:ok,
     assign(socket,
       products: Shop.products(),
       categories: Shop.categories(),
       category: "All items",
       q: "",
       cart: %{},
       basket_open: false,
       menu_open: false,
       page_title: "Everyday living"
     )}
  end

  def handle_event("search", %{"q" => q}, socket),
    do: {:noreply, assign(socket, q: String.slice(q, 0, 100))}

  def handle_event("category", %{"name" => name}, socket) do
    category = if name in ["All items" | Shop.categories()], do: name, else: "All items"
    {:noreply, socket |> assign(:category, category) |> push_event("scroll-catalogue", %{})}
  end

  def handle_event("add", %{"id" => id}, socket) do
    if Enum.any?(socket.assigns.products, &(to_string(&1.id) == id)) do
      {:noreply, update(socket, :cart, &Map.update(&1, id, 1, fn q -> min(q + 1, 99) end))}
    else
      {:noreply, socket}
    end
  end

  def handle_event("minus", %{"id" => id}, socket) do
    cart =
      Map.update(socket.assigns.cart, id, 0, &max(&1 - 1, 0))
      |> Map.reject(fn {_, q} -> q == 0 end)

    {:noreply, assign(socket, :cart, cart)}
  end

  def handle_event("basket", _, socket), do: {:noreply, update(socket, :basket_open, &(!&1))}
  def handle_event("menu", _, socket), do: {:noreply, update(socket, :menu_open, &(!&1))}

  def handle_info(:shop_changed, socket),
    do: {:noreply, assign(socket, :products, Shop.products())}

  def visible_products(products, category, q) do
    Enum.filter(products, fn p ->
      (category == "All items" or p.category == category) and
        String.contains?(
          String.downcase(p.name <> " " <> p.sku <> " " <> p.category),
          String.downcase(q)
        )
    end)
  end

  def cart_items(products, cart),
    do: Enum.filter(products, &(Map.get(cart, to_string(&1.id), 0) > 0))

  def cart_total(cart), do: Enum.sum(Map.values(cart))

  def enquiry_url(products, cart) do
    lines =
      Enum.map_join(cart_items(products, cart), "\n", fn p ->
        "- #{p.name} (SKU: #{p.sku}) × #{cart[to_string(p.id)]}"
      end)

    whatsapp(
      "Hello Robinah’s Shop, I’d like to enquire about these products:\n#{lines}\nPlease confirm current prices and collection/delivery arrangements."
    )
  end

  def whatsapp(message \\ "Hello Robinah’s Shop, I’d like to enquire about your products."),
    do: "https://wa.me/256774843183?text=" <> URI.encode_www_form(message)

  def collection_image(index),
    do:
      Enum.at(
        [
          "kitchen-essentials.jpg",
          "travel-everyday-bags.jpg",
          "bedding-comfort.jpg",
          "household-storage.jpg",
          "school-essentials.jpg"
        ],
        index
      )
end
