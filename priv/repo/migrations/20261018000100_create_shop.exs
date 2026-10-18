defmodule RobinahsShop.Repo.Migrations.CreateShop do
  use Ecto.Migration

  def change do
    create table(:staff) do
      add :email, :string, null: false, collate: nocase_collate()
      add :name, :string, null: false
      add :password_hash, :string, null: false
      add :role, :string, null: false
      add :active, :boolean, null: false, default: true
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:staff, [:email])

    create table(:staff_sessions) do
      add :token_hash, :string, null: false
      add :staff_id, references(:staff, on_delete: :delete_all), null: false
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:staff_sessions, [:token_hash])
    create index(:staff_sessions, [:staff_id])

    create table(:products) do
      add :sku, :string, null: false, collate: nocase_collate()
      add :name, :string, null: false
      add :category, :string, null: false
      add :unit, :string, null: false, default: "piece"
      add :image, :string, null: false, default: "/resources/kitchen-essentials.jpg"

      add :price, :integer,
        null: false,
        default: 0,
        check: %{name: "price_nonnegative", expr: "price >= 0"}

      add :stock, :integer,
        null: false,
        default: 0,
        check: %{name: "stock_nonnegative", expr: "stock >= 0"}

      add :active, :boolean, null: false, default: true
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:products, [:sku])

    create table(:receivings) do
      add :request_id, :string, null: false
      add :fingerprint, :string, null: false
      add :product_id, references(:products), null: false
      add :staff_id, references(:staff), null: false
      add :quantity, :integer, null: false
      add :buying_cost, :integer
      add :supplier, :string
      add :reference, :string
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:receivings, [:request_id])
    create index(:receivings, [:inserted_at])

    create table(:sales) do
      add :request_id, :string, null: false
      add :fingerprint, :string, null: false
      add :staff_id, references(:staff), null: false
      add :total, :integer, null: false
      add :payment_method, :string, null: false
      add :cash_received, :integer
      add :change, :integer
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:sales, [:request_id])
    create index(:sales, [:inserted_at])

    create table(:sale_items) do
      add :sale_id, references(:sales, on_delete: :delete_all), null: false
      add :product_id, references(:products), null: false
      add :sku, :string, null: false
      add :name, :string, null: false
      add :quantity, :integer, null: false
      add :unit_price, :integer, null: false
    end

    create index(:sale_items, [:sale_id])
  end

  defp nocase_collate do
    if repo().__adapter__() == Ecto.Adapters.SQLite3, do: :nocase
  end
end
