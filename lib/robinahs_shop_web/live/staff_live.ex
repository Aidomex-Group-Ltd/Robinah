defmodule RobinahsShopWeb.StaffLive do
  use RobinahsShopWeb, :live_view

  alias RobinahsShop.StockList
  alias RobinahsShopWeb.Cart

  @empty_receiving %{
    "product_id" => "",
    "quantity" => "1",
    "buying_cost" => "",
    "supplier" => "",
    "reference" => "",
    "request_id" => nil
  }

  def mount(_, _, socket) do
    if connected?(socket), do: Shop.subscribe()
    user = socket.assigns.current_user

    socket =
      assign(socket,
        products: Shop.all_products(user),
        categories: Shop.categories(),
        q: "",
        category: "All items",
        cart: Cart.new(),
        receiving_form: to_form(receiving_params(), as: :receiving),
        sale_form: to_form(%{"payment_method" => "Cash", "cash_received" => ""}, as: :sale),
        sale_request_id: Ecto.UUID.generate(),
        product_id: nil,
        product_form: to_form(Shop.change_product()),
        team_form: to_form(%{}, as: :staff),
        filters: %{"from" => "", "to" => ""},
        report: nil,
        sales: Shop.recent_sales(user),
        receivings: Shop.recent_receivings(user),
        expenses: Shop.recent_expenses(user),
        expense_categories: Shop.expense_categories(),
        expense_form: to_form(expense_params(), as: :expense),
        team: Accounts.list_staff(user),
        receipt: nil,
        inv_q: "",
        inv_filter: "all",
        inv_page: 1,
        inventory: nil,
        review_id: nil,
        review_entry: nil,
        review_form: to_form(%{}, as: :review),
        more_open: false,
        can_sale: Accounts.allowed?(user, :sale),
        can_receive: Accounts.allowed?(user, :receive),
        can_manage: Accounts.allowed?(user, :manage),
        can_report: Accounts.allowed?(user, :report),
        can_expense: Accounts.allowed?(user, :expense),
        can_team: Accounts.allowed?(user, :team)
      )

    {:ok, socket}
  end

  def handle_params(_, _, socket) do
    permission =
      %{
        pos: :sale,
        receiving: :receive,
        products: :manage,
        reports: :report,
        expenses: :expense,
        team: :team
      }[socket.assigns.live_action]

    if Accounts.allowed?(socket.assigns.current_user, permission) do
      socket =
        socket
        |> assign(:page_title, title(socket.assigns.live_action))
        |> assign(:more_open, false)

      socket =
        if socket.assigns.live_action == :receiving,
          do: load_inventory(socket),
          else: socket

      {:noreply,
       if(socket.assigns.live_action == :reports, do: load_report(socket), else: socket)}
    else
      to =
        if Accounts.allowed?(socket.assigns.current_user, :sale),
          do: "/staff/pos",
          else: "/staff/receiving"

      if permission == :receive and not Accounts.allowed?(socket.assigns.current_user, :sale) do
        {:noreply, redirect(socket, to: "/staff/sign-in")}
      else
        {:noreply,
         socket |> put_flash(:error, "Your role does not permit that screen.") |> redirect(to: to)}
      end
    end
  end

  def handle_event("search", %{"q" => q}, socket),
    do: {:noreply, assign(socket, :q, String.slice(q, 0, 100))}

  def handle_event("category", %{"name" => name}, socket) do
    category = if name in ["All items" | Shop.categories()], do: name, else: "All items"
    {:noreply, assign(socket, :category, category)}
  end

  def handle_event("show-all", _, socket),
    do: {:noreply, assign(socket, q: "", category: "All items")}

  def handle_event("add", %{"id" => id}, socket) when is_binary(id) and byte_size(id) <= 40 do
    if Accounts.allowed?(socket.assigns.current_user, :sale) and
         Enum.any?(socket.assigns.products, &(to_string(&1.id) == id and &1.active)) do
      socket = update(socket, :cart, &Cart.add(&1, id))
      # Bring the billing console into view the moment an item is selected.
      {:noreply, push_event(socket, "scroll-basket", %{})}
    else
      {:noreply, put_flash(socket, :error, "Product or permission unavailable.")}
    end
  end

  def handle_event("add", _, socket), do: {:noreply, socket}

  def handle_event("minus", %{"id" => id}, socket) when is_binary(id) do
    if Accounts.allowed?(socket.assigns.current_user, :sale) do
      {:noreply, update(socket, :cart, &Cart.minus(&1, id))}
    else
      {:noreply, put_flash(socket, :error, "Your role does not permit sales.")}
    end
  end

  def handle_event("remove", %{"id" => id}, socket) when is_binary(id) do
    if Accounts.allowed?(socket.assigns.current_user, :sale) do
      {:noreply, update(socket, :cart, &Cart.remove(&1, id))}
    else
      {:noreply, put_flash(socket, :error, "Your role does not permit sales.")}
    end
  end

  def handle_event("review-basket", _, socket) do
    {:noreply, push_event(socket, "scroll-basket", %{})}
  end

  def handle_event("more-toggle", _, socket),
    do: {:noreply, update(socket, :more_open, &(!&1))}

  def handle_event("sale-change", %{"sale" => params}, socket),
    do: {:noreply, assign(socket, :sale_form, to_form(params, as: :sale))}

  def handle_event("set-payment", %{"method" => method}, socket) do
    if method in Shop.payment_methods() do
      params = Map.put(socket.assigns.sale_form.params, "payment_method", method)
      {:noreply, assign(socket, :sale_form, to_form(params, as: :sale))}
    else
      {:noreply, socket}
    end
  end

  def handle_event("post-sale", %{"sale" => params}, socket) do
    cond do
      socket.assigns.cart == %{} ->
        {:noreply, put_flash(socket, :error, "Add at least one item before checkout.")}

      unconfirmed_prices?(socket.assigns.products, socket.assigns.cart) ->
        {:noreply,
         put_flash(socket, :error, "Confirm unit prices for every item before checkout.")}

      true ->
        attrs =
          Map.merge(params, %{
            "request_id" => socket.assigns.sale_request_id,
            "items" => Cart.to_sale_items(socket.assigns.cart)
          })

        case Shop.post_sale(socket.assigns.current_user, attrs) do
          {:ok, sale} ->
            {:noreply,
             socket
             |> assign(
               cart: Cart.new(),
               receipt: sale,
               sale_request_id: Ecto.UUID.generate(),
               sale_form: to_form(%{"payment_method" => "Cash", "cash_received" => ""}, as: :sale)
             )
             |> refresh()
             |> push_event("focus-receipt", %{})
             |> put_flash(
               :info,
               "Sale posted. Receipt RS-#{sale.id}. Payment method is a manual record."
             )}

          {:error, error} ->
            {:noreply, put_flash(socket, :error, Shop.error_message(error))}
        end
    end
  end

  def handle_event("receive-change", %{"receiving" => params}, socket),
    do: {:noreply, assign(socket, :receiving_form, to_form(params, as: :receiving))}

  def handle_event("receive", %{"receiving" => params}, socket) do
    case Shop.receive(socket.assigns.current_user, params) do
      {:ok, receiving} ->
        form = to_form(receiving_params(), as: :receiving)

        {:noreply,
         socket
         |> assign(:receiving_form, form)
         |> refresh()
         |> put_flash(:info, "Receiving GR-#{receiving.id} saved and stock increased.")}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, Shop.error_message(error))}
    end
  end

  def handle_event("inventory-search", %{"inv_q" => q}, socket) do
    socket = socket |> assign(:inv_q, String.slice(q, 0, 100)) |> assign(:inv_page, 1)
    {:noreply, load_inventory(socket)}
  end

  def handle_event("inventory-filter", %{"filter" => filter}, socket) do
    filter = if filter in StockList.filters(), do: filter, else: "all"
    socket = socket |> assign(:inv_filter, filter) |> assign(:inv_page, 1)
    {:noreply, load_inventory(socket)}
  end

  def handle_event("inventory-page", %{"page" => page}, socket) do
    socket = assign(socket, :inv_page, page)
    {:noreply, load_inventory(socket)}
  end

  def handle_event("review-entry", %{"id" => id}, socket) do
    entry = Enum.find(socket.assigns.inventory.entries, &(to_string(&1.id) == id))

    if entry && Accounts.allowed?(socket.assigns.current_user, :manage) do
      {:noreply, socket |> assign(review_id: entry.id) |> load_inventory()}
    else
      {:noreply, put_flash(socket, :error, "Entry or permission unavailable.")}
    end
  end

  def handle_event("cancel-review", _, socket),
    do: {:noreply, socket |> assign(review_id: nil) |> load_inventory()}

  def handle_event("confirm-entry", %{"review" => params}, socket) do
    case StockList.confirm_entry(socket.assigns.current_user, params["entry_id"], params) do
      {:ok, entry} ->
        {:noreply,
         socket
         |> assign(review_id: nil)
         |> load_inventory()
         |> put_flash(
           :info,
           "Entry #{pad(entry.number)} confirmed at #{money(entry.confirmed_unit_price)}." <>
             if(entry.product_id, do: " The linked product price was updated.", else: "")
         )}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, review_error(error))}
    end
  end

  def handle_event("edit-product", %{"id" => id}, socket) do
    product = Enum.find(socket.assigns.products, &(to_string(&1.id) == id))

    if product && Accounts.allowed?(socket.assigns.current_user, :manage) do
      {:noreply,
       assign(socket, product_id: product.id, product_form: to_form(Shop.change_product(product)))}
    else
      {:noreply, put_flash(socket, :error, "Product or permission unavailable.")}
    end
  end

  def handle_event("new-product", _, socket),
    do: {:noreply, assign(socket, product_id: nil, product_form: to_form(Shop.change_product()))}

  def handle_event("save-product", %{"product" => params}, socket) do
    case Shop.save_product(socket.assigns.current_user, socket.assigns.product_id, params) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(product_id: nil, product_form: to_form(Shop.change_product()))
         |> refresh()
         |> put_flash(:info, "Product saved. Receive stock through Goods receiving.")}

      {:error, %Ecto.Changeset{} = cs} ->
        {:noreply,
         socket
         |> assign(:product_form, to_form(Map.put(cs, :action, :insert)))
         |> put_flash(:error, Shop.error_message(cs))}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, Shop.error_message(error))}
    end
  end

  def handle_event("filter-report", %{"from" => first, "to" => last}, socket),
    do: {:noreply, socket |> assign(:filters, %{"from" => first, "to" => last}) |> load_report()}

  def handle_event("clear-dates", _, socket),
    do: {:noreply, socket |> assign(:filters, %{"from" => "", "to" => ""}) |> load_report()}

  def handle_event("expense-change", %{"expense" => params}, socket),
    do: {:noreply, assign(socket, :expense_form, to_form(params, as: :expense))}

  def handle_event("record-expense", %{"expense" => params}, socket) do
    case Shop.record_expense(socket.assigns.current_user, params) do
      {:ok, _expense} ->
        {:noreply,
         socket
         |> assign(:expense_form, to_form(expense_params(), as: :expense))
         |> refresh()
         |> put_flash(:info, "Expense recorded against the shop ledger.")}

      {:error, %Ecto.Changeset{} = cs} ->
        {:noreply,
         socket
         |> assign(:expense_form, to_form(Map.put(cs, :action, :insert), as: :expense))
         |> put_flash(:error, Shop.error_message(cs))}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, Shop.error_message(error))}
    end
  end

  def handle_event("create-staff", %{"staff" => attrs}, socket) do
    case Accounts.create_staff(socket.assigns.current_user, attrs) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(
           team_form: to_form(%{}, as: :staff),
           team: Accounts.list_staff(socket.assigns.current_user)
         )
         |> put_flash(:info, "Staff account created.")}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, Shop.error_message(error))}
    end
  end

  def handle_event("deactivate-staff", %{"id" => id}, socket) do
    case Accounts.deactivate_staff(socket.assigns.current_user, id) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:team, Accounts.list_staff(socket.assigns.current_user))
         |> put_flash(:info, "Staff account deactivated and sessions revoked.")}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, Shop.error_message(error))}
    end
  end

  def handle_event("refresh", _, socket), do: {:noreply, refresh(socket)}
  def handle_event("print", _, socket), do: {:noreply, push_event(socket, "print", %{})}

  def handle_event("close-receipt", _, socket),
    do: {:noreply, assign(socket, receipt: nil)}

  def handle_info(:shop_changed, socket), do: {:noreply, refresh(socket)}

  defp refresh(socket) do
    user = socket.assigns.current_user

    socket =
      assign(socket,
        products: Shop.all_products(user),
        sales: Shop.recent_sales(user),
        receivings: Shop.recent_receivings(user),
        expenses: Shop.recent_expenses(user)
      )

    socket =
      if socket.assigns.live_action == :receiving,
        do: load_inventory(socket),
        else: socket

    if socket.assigns.live_action in [:reports, :expenses], do: load_report(socket), else: socket
  end

  defp load_inventory(socket) do
    StockList.ensure_reference!()

    inventory =
      StockList.list_entries(%{
        "q" => socket.assigns.inv_q,
        "filter" => socket.assigns.inv_filter,
        "page" => socket.assigns.inv_page
      })

    review_entry = Enum.find(inventory.entries, &(&1.id == socket.assigns.review_id))

    socket
    |> assign_if(:inv_page, inventory.page, inventory.page != socket.assigns.inv_page)
    |> assign_if(:review_id, nil, socket.assigns.review_id && is_nil(review_entry))
    |> assign(:inventory, inventory)
    |> assign(:review_entry, review_entry)
  end

  defp assign_if(socket, key, value, true), do: assign(socket, key, value)
  defp assign_if(socket, _key, _value, _), do: socket

  defp load_report(socket) do
    case Shop.report(socket.assigns.current_user, socket.assigns.filters) do
      {:ok, report} ->
        assign(socket, :report, report)

      {:error, error} ->
        socket |> assign(:report, nil) |> put_flash(:error, Shop.error_message(error))
    end
  end

  defp receiving_params, do: %{@empty_receiving | "request_id" => Ecto.UUID.generate()}

  defp expense_params do
    %{
      "spent_on" => Date.to_iso8601(Date.utc_today()),
      "category" => hd(Shop.expense_categories()),
      "description" => "",
      "amount" => ""
    }
  end

  defp review_error(:price_required), do: "Enter the confirmed unit price before confirming."
  defp review_error(:not_found), do: "That reference entry no longer exists."
  defp review_error(:forbidden), do: "Your staff role does not permit confirming prices."
  defp review_error(error), do: Shop.error_message(error)

  def title(:pos), do: "Point of sale"
  def title(:receiving), do: "Inventory & receiving"
  def title(:products), do: "Product catalogue"
  def title(:reports), do: "Sales analytics & reports"
  def title(:expenses), do: "Operating expenses"
  def title(:team), do: "Staff accounts"

  def cart_count(cart), do: Cart.count(cart)

  def total(products, cart), do: Cart.total(products, cart)

  @doc "Number of distinct products currently selected in the sale."
  def line_count(cart), do: map_size(cart)

  @doc "Spreadsheet rows: one per selected product with its sub total."
  def cart_line(products, cart) do
    Enum.map(Cart.items(products, cart), fn p ->
      %{product: p, quantity: Map.get(cart, to_string(p.id), 0), total: Cart.row_total(p, cart)}
    end)
  end

  @doc "Sub total (sum of every selected line). VAT is not charged at the counter."
  def subtotal(products, cart), do: Cart.total(products, cart)

  @doc "Total number of units across all selected lines."
  def total_units(_products, cart), do: cart_count(cart)

  @doc "Grand total posted at checkout: sub total with no tax added."
  def grand_total(products, cart), do: subtotal(products, cart)

  def visible_products(products, category, q) do
    term = String.downcase(q)

    Enum.filter(products, fn p ->
      p.active and
        (category == "All items" or p.category == category) and
        String.contains?(String.downcase(p.name <> " " <> p.sku), term)
    end)
  end

  def unconfirmed_prices?(products, cart),
    do: Cart.has_unconfirmed_prices?(products, cart)

  def pad(number) when number < 10, do: "0#{number}"
  def pad(number), do: to_string(number)

  @doc """
  Product photographs available on disk, excluding brand artwork and the
  hashed copies produced by `mix phx.digest`.
  """
  def image_options do
    Path.join([:code.priv_dir(:robinahs_shop), "static", "resources"])
    |> File.ls!()
    |> Enum.filter(&Regex.match?(~r/^[a-zA-Z0-9_-]+\.(jpg|jpeg|png)$/, &1))
    |> Enum.reject(&String.starts_with?(&1, "robinahs-"))
    |> Enum.reject(&Regex.match?(~r/-[0-9a-f]{32}\.(jpg|jpeg|png)$/, &1))
    |> Enum.sort()
  end
end
