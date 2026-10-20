defmodule RobinahsShop.ShopTest do
  use RobinahsShop.DataCase, async: false

  setup do
    owner = owner_fixture()
    product = product_fixture(owner)
    %{owner: owner, product: product}
  end

  test "receiving persists history and stock exactly once", %{owner: owner, product: p} do
    attrs = receive_attrs(p)
    assert {:ok, first} = Shop.receive(owner, attrs)
    assert {:ok, second} = Shop.receive(owner, attrs)
    assert first.id == second.id
    assert Repo.get!(Product, p.id).stock == 10
    assert Repo.aggregate(Receiving, :count) == 1
    assert {:error, :request_reused} = Shop.receive(owner, Map.put(attrs, "quantity", 20))
    assert Repo.get!(Product, p.id).stock == 10
  end

  test "sale prices come from the database and duplicate posts do not decrement twice", %{
    owner: owner,
    product: p
  } do
    assert {:ok, _} = Shop.receive(owner, receive_attrs(p))

    attrs =
      sale_attrs(p)
      |> Map.put("total", 1)
      |> Map.update!("items", fn [line] -> [Map.put(line, "unit_price", 1)] end)

    assert {:ok, sale} = Shop.post_sale(owner, attrs)
    assert sale.total == 4_000
    assert sale.change == 6_000
    assert {:ok, repeat} = Shop.post_sale(owner, attrs)
    assert repeat.id == sale.id
    assert Repo.get!(Product, p.id).stock == 8
    assert Repo.aggregate(Sale, :count) == 1
  end

  test "multi-line overselling rolls every stock change back", %{owner: owner, product: p} do
    {:ok, _} = Shop.receive(owner, receive_attrs(p))
    empty = product_fixture(owner)

    attrs =
      sale_attrs(p)
      |> Map.put("items", [
        %{"product_id" => p.id, "quantity" => 2},
        %{"product_id" => empty.id, "quantity" => 1}
      ])

    assert {:error, :insufficient_stock} = Shop.post_sale(owner, attrs)
    assert Repo.get!(Product, p.id).stock == 10
    assert Repo.aggregate(Sale, :count) == 0
  end

  test "duplicate product lines are combined before the stock check", %{owner: owner, product: p} do
    {:ok, _} = Shop.receive(owner, receive_attrs(p, 3))

    attrs =
      sale_attrs(p)
      |> Map.put("items", [
        %{"product_id" => p.id, "quantity" => 2},
        %{"product_id" => p.id, "quantity" => 2}
      ])

    assert {:error, :insufficient_stock} = Shop.post_sale(owner, attrs)
    assert Repo.get!(Product, p.id).stock == 3
  end

  test "insufficient cash and unset prices cannot post a sale", %{owner: owner, product: p} do
    {:ok, _} = Shop.receive(owner, receive_attrs(p))

    assert {:error, :insufficient_cash} =
             Shop.post_sale(owner, Map.put(sale_attrs(p), "cash_received", 1))

    {:ok, _} = Shop.save_product(owner, p.id, %{"price" => 0})
    assert {:error, :price_unset} = Shop.post_sale(owner, sale_attrs(p))
    assert Repo.get!(Product, p.id).stock == 10
  end

  test "roles are checked against current database state", %{owner: owner, product: p} do
    cashier = staff_fixture(owner, "cashier")
    receiver = staff_fixture(owner, "receiver")
    refute Accounts.allowed?(%{cashier | role: :owner}, :manage)
    assert {:error, :forbidden} = Shop.receive(cashier, receive_attrs(p))
    assert {:error, :forbidden} = Shop.post_sale(receiver, sale_attrs(p))
    assert {:error, :forbidden} = Shop.report(cashier)
    {:ok, _} = Accounts.deactivate_staff(owner, cashier.id)
    assert {:error, :forbidden} = Shop.post_sale(cashier, sale_attrs(p))
  end

  test "invalid and fractional receiving quantities leave stock unchanged", %{
    owner: owner,
    product: p
  } do
    for quantity <- [0, -1, "1.5", "abc"] do
      assert {:error, :invalid_input} =
               Shop.receive(owner, Map.put(receive_attrs(p), "quantity", quantity))
    end

    assert Repo.get!(Product, p.id).stock == 0
  end

  test "report filters use East Africa dates and export all matching records", %{
    owner: owner,
    product: p
  } do
    {:ok, _} = Shop.receive(owner, receive_attrs(p))
    {:ok, sale} = Shop.post_sale(owner, sale_attrs(p))
    sale |> Ecto.Changeset.change(inserted_at: ~U[2030-12-31 22:00:00.000000Z]) |> Repo.update!()

    assert {:ok, %{count: 1, total: 4_000}} =
             Shop.report(owner, %{"from" => "2031-01-01", "to" => "2031-01-01"})

    assert {:ok, %{count: 0}} =
             Shop.report(owner, %{"from" => "2030-12-31", "to" => "2030-12-31"})

    assert {:ok, csv} = Shop.export_csv(owner, %{"from" => "2031-01-01"})
    assert csv =~ "RS-#{sale.id}"
    assert {:error, :invalid_dates} = Shop.report(owner, %{"from" => "invalid"})
  end

  test "expenses are recorded with whole UGX amounts and rejected when invalid", %{
    owner: owner
  } do
    assert {:ok, expense} = Shop.record_expense(owner, expense_attrs(%{"amount" => "50000"}))
    assert expense.amount == 50_000
    assert expense.category == "Utilities"
    assert expense.staff_id == owner.id
    assert Repo.aggregate(Expense, :count) == 1

    assert {:error, %Ecto.Changeset{}} =
             Shop.record_expense(owner, expense_attrs(%{"amount" => "0"}))

    assert {:error, %Ecto.Changeset{}} =
             Shop.record_expense(owner, expense_attrs(%{"amount" => "100.5"}))

    assert {:error, %Ecto.Changeset{}} =
             Shop.record_expense(owner, expense_attrs(%{"category" => "Bribes"}))

    assert Repo.aggregate(Expense, :count) == 1
  end

  test "only owners and managers may record expenses", %{owner: owner, product: p} do
    cashier = staff_fixture(owner, "cashier")
    receiver = staff_fixture(owner, "receiver")

    assert {:error, :forbidden} = Shop.record_expense(cashier, expense_attrs())
    assert {:error, :forbidden} = Shop.record_expense(receiver, expense_attrs())
    refute Accounts.allowed?(cashier, :expense)
    assert Accounts.allowed?(owner, :expense)
    assert p
  end

  test "profit report subtracts average buying cost and expenses from revenue", %{
    owner: owner,
    product: p
  } do
    {:ok, _} = Shop.receive(owner, Map.put(receive_attrs(p, 10), "buying_cost", "1000"))
    {:ok, _} = Shop.post_sale(owner, sale_attrs(p, 4))
    {:ok, _} = Shop.record_expense(owner, expense_attrs(%{"amount" => "1500"}))

    assert {:ok, report} = Shop.report(owner, %{})

    assert report.total == 8_000
    assert report.cogs == 4_000
    assert report.gross_profit == 4_000
    assert report.expenses == 1_500
    assert report.net_profit == 2_500
  end

  test "expense totals respect the report date range", %{owner: owner} do
    {:ok, _} = Shop.record_expense(owner, expense_attrs(%{"amount" => "1000"}))
    old = Date.add(Date.utc_today(), -30)

    {:ok, _} =
      Shop.record_expense(
        owner,
        expense_attrs(%{"amount" => "7000", "spent_on" => Date.to_iso8601(old)})
      )

    assert {:ok, report} = Shop.report(owner, %{})
    assert report.expenses == 8_000

    today = Date.to_iso8601(Date.utc_today())
    assert {:ok, today_report} = Shop.report(owner, %{"from" => today, "to" => today})
    assert today_report.expenses == 1_000
  end

  test "products without a recorded buying cost contribute zero to COGS", %{
    owner: owner,
    product: p
  } do
    {:ok, _} = Shop.receive(owner, Map.put(receive_attrs(p, 5), "buying_cost", ""))
    {:ok, _} = Shop.post_sale(owner, sale_attrs(p, 2))

    assert {:ok, report} = Shop.report(owner, %{})
    assert report.total == 4_000
    assert report.cogs == 0
  end

  test "catalogue seeding is repeatable without replacing configured prices", %{owner: owner} do
    Shop.seed_catalogue()
    Shop.seed_catalogue()

    item = Repo.get_by!(Product, sku: "RSH-001")
    {:ok, _} = Shop.save_product(owner, item.id, %{"price" => 15_000})
    Shop.seed_catalogue()
    assert Repo.get!(Product, item.id).price == 15_000
  end

  test "every handwritten row becomes a product with its own photo and seeded prices/stock" do
    Shop.seed_catalogue()

    products =
      for number <- 1..Catalogue.count(), do: Repo.get_by!(Product, sku: Catalogue.sku(number))

    assert length(products) == 36
    assert Enum.all?(products, &(&1.price > 0))
    assert Enum.all?(products, &(&1.stock == 10))

    images = Enum.map(products, & &1.image)

    assert Enum.all?(images, fn
             nil -> true
             path -> String.starts_with?(path, "/resources/item-")
           end)

    photos = Enum.reject(images, &is_nil/1)
    assert photos != []
    assert length(Enum.uniq(photos)) == length(photos)

    retired = Repo.all(from p in Product, where: fragment("upper(?) LIKE 'DEMO-%'", p.sku))
    assert Enum.all?(retired, &(&1.active == false))
  end

  test "rows outside the catalogue are retired when they repeat a note row with a placeholder photo",
       %{
         owner: owner
       } do
    placeholder = product_fixture(owner, %{"name" => "Torch", "sku" => "OLD-TORCH"})
    other_name = product_fixture(owner, %{"name" => "Waffle iron"})

    own_photo =
      product_fixture(owner, %{"name" => "Torch", "image" => "/resources/item-06-torch.jpg"})

    Shop.seed_catalogue()

    refute Repo.get!(Product, placeholder.id).active
    assert Repo.get!(Product, other_name.id).active
    assert Repo.get!(Product, own_photo.id).active
  end

  test "seeding consolidates legacy placeholder rows onto the catalogue photo, price and stock",
       %{owner: owner} do
    legacy =
      product_fixture(owner, %{
        "name" => "Cup with numbers",
        "sku" => "CUP-NUM-01",
        "price" => 1_000,
        "image" => "/resources/kitchen-essentials.jpg"
      })

    {:ok, _} = Shop.receive(owner, receive_attrs(legacy, 24))

    Shop.seed_catalogue()

    row = Repo.get_by!(Product, sku: "RSH-001")
    assert row.image == "/resources/item-01-cup-with-numbers.jpg"
    assert row.price == 5_000
    assert row.stock == 24 + 10
    refute Repo.get!(Product, legacy.id).active
  end

  test "seeding upgrades catalogue rows still carrying a legacy placeholder photo" do
    Shop.seed_catalogue()

    row =
      Repo.get_by!(Product, sku: "RSH-006")
      |> Ecto.Changeset.change(image: "/resources/kitchen-essentials.jpg", price: 2_000)
      |> Repo.update!()

    Shop.seed_catalogue()

    upgraded = Repo.get!(Product, row.id)
    assert upgraded.image == "/resources/item-06-torch.jpg"
    assert upgraded.price == 2_000
  end
end
