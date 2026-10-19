defmodule RobinahsShopWeb.HTTPTest do
  use RobinahsShop.DataCase, async: false
  import Phoenix.ConnTest
  @endpoint RobinahsShopWeb.Endpoint
  test "public catalogue renders recovered content and local images" do
    Shop.seed_catalogue()
    html = build_conn() |> get("/") |> html_response(200)
    assert html =~ "Good things for"
    assert html =~ "robinahs-shop-photo.jpg"
    assert html =~ "wa.me/256774843183"

    cards =
      html
      |> Floki.parse_document!()
      |> Floki.find("#catalogue-products .product-card")

    assert length(cards) == 36

    photos = cards |> Enum.flat_map(&Floki.find(&1, ".product-photo img"))
    assert length(photos) == 36

    sources = photos |> Enum.flat_map(&Floki.attribute(&1, "src"))
    assert length(Enum.uniq(sources)) == length(sources)
    assert Enum.all?(sources, &String.starts_with?(&1, "/resources/item-"))
  end

  test "launch screen has a no-JavaScript dismissal fallback" do
    html = build_conn() |> get("/") |> html_response(200)
    assert html =~ ~s(id="brand-launch")
    assert html =~ "<noscript>"
    assert html =~ ".launch-screen"
  end

  test "staff tools redirect anonymous visitors and CSV is protected" do
    assert build_conn() |> get("/staff/pos") |> redirected_to() == "/staff/sign-in"
    assert build_conn() |> get("/staff/reports.csv") |> response(403) =~ "Owner or manager"
  end

  test "owner can open the staff tools and cashier cannot export reports" do
    owner = owner_fixture()
    token = Accounts.create_session(owner)

    html =
      build_conn()
      |> init_test_session(%{staff_token: token})
      |> get("/staff/products")
      |> html_response(200)

    assert html =~ "Products &amp; prices"
    cashier = staff_fixture(owner, "cashier")
    token = Accounts.create_session(cashier)

    assert build_conn()
           |> init_test_session(%{staff_token: token})
           |> get("/staff/reports.csv")
           |> response(403) =~ "Owner or manager"
  end
end
