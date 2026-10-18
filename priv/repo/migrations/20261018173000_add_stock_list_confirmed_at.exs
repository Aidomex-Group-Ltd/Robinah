defmodule RobinahsShop.Repo.Migrations.AddStockListConfirmedAt do
  use Ecto.Migration

  def change do
    alter table(:stock_list_entries) do
      add :confirmed_at, :utc_datetime_usec
    end
  end
end
