defmodule RobinahsShop.Repo.Migrations.CreateExpenses do
  use Ecto.Migration

  def change do
    create table(:expenses) do
      add :spent_on, :date, null: false

      add :amount, :integer,
        null: false,
        check: %{name: "amount_positive", expr: "amount > 0"}

      add :category, :string, null: false
      add :description, :string, null: false
      add :staff_id, references(:staff), null: false
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:expenses, [:spent_on])
  end
end
