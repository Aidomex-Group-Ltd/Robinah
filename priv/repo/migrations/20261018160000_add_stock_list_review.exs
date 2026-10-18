defmodule RobinahsShop.Repo.Migrations.AddStockListReview do
  use Ecto.Migration

  def change do
    alter table(:products) do
      add :reorder_level, :integer,
        null: true,
        check: %{name: "reorder_level_nonnegative", expr: "reorder_level >= 0"}
    end

    create table(:stock_list_entries) do
      add :number, :integer, null: false
      add :item, :string, null: false
      add :quantity_as_listed, :string, null: false
      add :amount_as_written, :string, null: false
      add :needs_name_review, :boolean, null: false, default: false
      add :needs_amount_review, :boolean, null: false, default: false
      add :notes, :string
      add :status, :string, null: false, default: "pending"
      add :confirmed_unit_price, :integer
      add :product_id, references(:products, on_delete: :nilify_all)
      add :confirmed_by_staff_id, references(:staff, on_delete: :nilify_all)
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:stock_list_entries, [:number])
    create index(:stock_list_entries, [:status])
    create index(:stock_list_entries, [:product_id])
  end
end
