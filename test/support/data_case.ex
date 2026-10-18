defmodule RobinahsShop.DataCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      alias RobinahsShop.{Accounts, Shop, Repo, Product, Sale, Receiving}
      import RobinahsShop.DataCase
    end
  end

  setup do
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(RobinahsShop.Repo, shared: true)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(owner) end)
    :ok
  end

  def owner_fixture do
    {:ok, owner} =
      RobinahsShop.Accounts.bootstrap_owner("owner@example.com", "test-password-long-enough")

    owner
  end

  def staff_fixture(owner, role) do
    {:ok, user} =
      RobinahsShop.Accounts.create_staff(owner, %{
        "email" => "#{role}@example.com",
        "name" => role,
        "role" => role,
        "password" => "test-password-long-enough"
      })

    user
  end

  def product_fixture(owner, attrs \\ %{}) do
    defaults = %{
      "sku" => "ITEM-#{System.unique_integer([:positive])}",
      "name" => "Kitchen set",
      "category" => "Home & Kitchen",
      "price" => 2_000,
      "unit" => "set",
      "image" => "/resources/kitchen-essentials.jpg"
    }

    {:ok, product} = RobinahsShop.Shop.save_product(owner, nil, Map.merge(defaults, attrs))
    product
  end

  def receive_attrs(product, quantity \\ 10),
    do: %{
      "request_id" => Ecto.UUID.generate(),
      "product_id" => product.id,
      "quantity" => quantity,
      "buying_cost" => "1000",
      "supplier" => "Supplier",
      "reference" => "DEL-1"
    }

  def sale_attrs(product, quantity \\ 2),
    do: %{
      "request_id" => Ecto.UUID.generate(),
      "items" => [%{"product_id" => product.id, "quantity" => quantity}],
      "payment_method" => "Cash",
      "cash_received" => "10000"
    }
end
