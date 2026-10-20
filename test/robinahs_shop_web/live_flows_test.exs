defmodule RobinahsShopWeb.LiveFlowsTest do
  use RobinahsShop.DataCase, async: false
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  import Plug.Conn, only: [get_resp_header: 2]
  @endpoint RobinahsShopWeb.Endpoint

  test "public search and enquiry basket work through LiveView" do
    Shop.seed_catalogue()
    {:ok, view, _} = live(build_conn(), "/")
    view |> form("#catalogue-search", %{q: "Torch"}) |> render_change()
    assert has_element?(view, "#catalogue-products .product-card", "Torch")
    refute has_element?(view, "#catalogue-products .product-card", "Ruler")
    view |> element(".product-bottom button", "Add to enquiry") |> render_click()
    view |> element(".trolley-button") |> render_click()
    assert has_element?(view, ".basket-drawer .basket-line", "Torch")
    assert has_element?(view, ".basket-drawer a[href*=\"wa.me\"]")
  end

  test "cart badge tracks quantity 0-1-2-1-0 and hides at zero" do
    Shop.seed_catalogue()
    {:ok, view, _} = live(build_conn(), "/")

    refute has_element?(view, ".trolley-button b")

    view |> form("#catalogue-search", %{q: "Torch"}) |> render_change()

    view |> element(".product-bottom button", "Add to enquiry") |> render_click()
    assert has_element?(view, ".trolley-button b", "1")

    view |> element(".product-bottom button", "Add to enquiry") |> render_click()
    assert has_element?(view, ".trolley-button b", "2")

    view |> element(".trolley-button") |> render_click()
    assert has_element?(view, ".basket-drawer .basket-line", "Torch")

    view |> element(".basket-line .quantity button[phx-click='minus']") |> render_click()
    assert has_element?(view, ".trolley-button b", "1")

    view |> element(".basket-line .quantity button[phx-click='minus']") |> render_click()
    refute has_element?(view, ".trolley-button b")
    refute has_element?(view, ".basket-drawer .basket-line", "Torch")
  end

  test "POS sale table auto-increments row amounts and the grand total" do
    owner = owner_fixture()
    product = product_fixture(owner, %{"price" => 2500})
    conn = build_conn() |> init_test_session(%{staff_token: Accounts.create_session(owner)})
    {:ok, view, _} = live(conn, "/staff/receiving")

    view
    |> form("#receiving-form",
      receiving: %{product_id: to_string(product.id), quantity: "5", buying_cost: "1000"}
    )
    |> render_submit()

    view |> element("nav.staff-tabs a", "POS") |> render_click()
    view |> element("#item-row-#{product.id} .item-name") |> render_click()

    assert has_element?(view, ".sale-table tbody tr", product.name)
    assert has_element?(view, ".sale-table .col-unit", "UGX 2,500")
    assert has_element?(view, ".sale-table .col-total b", "UGX 2,500")
    assert has_element?(view, "#sale-subtotal", "UGX 2,500")
    assert has_element?(view, "#sale-grand-total", "UGX 2,500")

    view
    |> element(".sale-table tr .quantity button[phx-click='add']")
    |> render_click()

    assert has_element?(view, ".sale-table .col-qty .qty-value", "2")
    assert has_element?(view, ".sale-table .col-total b", "UGX 5,000")
    assert has_element?(view, "#sale-grand-total", "UGX 5,000")

    view
    |> element(".sale-table tr .quantity button[phx-click='minus']")
    |> render_click()

    assert has_element?(view, "#sale-grand-total", "UGX 2,500")
  end

  test "staff receiving and sale flow changes stock and issues a confirmed receipt" do
    owner = owner_fixture()
    product = product_fixture(owner)
    conn = build_conn() |> init_test_session(%{staff_token: Accounts.create_session(owner)})
    {:ok, view, _} = live(conn, "/staff/receiving")

    view
    |> form("#receiving-form",
      receiving: %{product_id: to_string(product.id), quantity: "5", buying_cost: "1000"}
    )
    |> render_submit()

    assert Repo.get!(Product, product.id).stock == 5
    view |> element("nav.staff-tabs a", "POS") |> render_click()
    assert_patch(view, "/staff/pos")
    view |> element("#item-row-#{product.id} .item-name") |> render_click()

    view
    |> form("#sale-form", sale: %{payment_method: "Cash", cash_received: "5000"})
    |> render_submit()

    assert has_element?(view, ".receipt", "Robinah’s Shop")
    assert has_element?(view, ".receipt .receipt-meta dd", "RS-#{Repo.one(Sale).id}")
    assert Repo.get!(Product, product.id).stock == 4
    assert Repo.aggregate(Sale, :count) == 1
  end

  test "selecting a payment method updates the checkout form" do
    owner = owner_fixture()
    product = product_fixture(owner)
    conn = build_conn() |> init_test_session(%{staff_token: Accounts.create_session(owner)})
    {:ok, view, _} = live(conn, "/staff/receiving")

    view
    |> form("#receiving-form",
      receiving: %{product_id: to_string(product.id), quantity: "5", buying_cost: "1000"}
    )
    |> render_submit()

    view |> element("nav.staff-tabs a", "POS") |> render_click()
    view |> element("#item-row-#{product.id} .item-name") |> render_click()

    view |> element(".pay-btn", "Mobile money") |> render_click()

    assert has_element?(
             view,
             "input[name='sale[payment_method]'][value='Manual mobile money record']"
           )

    view |> element(".pay-btn", "Card") |> render_click()
    assert has_element?(view, "input[name='sale[payment_method]'][value='Card (manual record)']")

    view |> element(".pay-btn", "Cash") |> render_click()
    assert has_element?(view, "input[name='sale[payment_method]'][value='Cash']")
  end

  test "inventory review page lists the imported stock list with pagination" do
    owner = owner_fixture()
    conn = build_conn() |> init_test_session(%{staff_token: Accounts.create_session(owner)})
    {:ok, view, _} = live(conn, "/staff/receiving")

    assert has_element?(view, ".inventory-table tbody tr", "Cup with numbers")
    assert has_element?(view, ".inventory-table tbody tr", "Nomi buckets")
    assert has_element?(view, ".page-summary", "Rows 1–9 of 36")
    assert has_element?(view, ".page-chip", "1")
    assert has_element?(view, ".inventory-table tbody tr", "Confirm")

    view |> element(".page-chip", "2") |> render_click()
    assert has_element?(view, ".page-summary", "Rows 10–18 of 36")

    view
    |> form("#inventory-search", %{"inv_q" => "Ruler"})
    |> render_change()

    assert has_element?(view, ".inventory-table tbody tr", "Ruler")
    assert has_element?(view, ".page-summary", "Rows 1–2 of 2")
  end

  test "owner confirms a listed unit price and the linked product price updates" do
    owner = owner_fixture()
    product = product_fixture(owner, %{"name" => "Cup with numbers", "price" => 0})
    conn = build_conn() |> init_test_session(%{staff_token: Accounts.create_session(owner)})
    {:ok, view, _} = live(conn, "/staff/receiving")

    view
    |> element(~s(button[aria-label="Confirm unit price for entry 01 Cup with numbers"]))
    |> render_click()

    assert has_element?(view, "#review-form")

    view
    |> form("#review-form",
      review: %{confirmed_unit_price: "1000", product_id: to_string(product.id)}
    )
    |> render_submit()

    assert Repo.get!(Product, product.id).price == 1000

    entry =
      RobinahsShop.StockList.list_entries(%{"q" => "Cup with numbers"})
      |> Map.get(:entries)
      |> hd()

    assert entry.confirmed_unit_price == 1000
    assert entry.status == :confirmed
  end

  test "inventory CSV export is available to authorised staff" do
    owner = owner_fixture()
    conn = build_conn() |> init_test_session(%{staff_token: Accounts.create_session(owner)})
    conn = get(conn, "/staff/inventory.csv")
    assert response(conn, 200)

    assert get_resp_header(conn, "content-disposition") == [
             "attachment; filename=\"robinahs-inventory-review.csv\""
           ]
  end
end
