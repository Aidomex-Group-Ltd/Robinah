defmodule RobinahsShop.Staff do
  use Ecto.Schema
  import Ecto.Changeset

  schema "staff" do
    field :email, :string
    field :name, :string
    field :password_hash, :string, redact: true
    field :password, :string, virtual: true, redact: true
    field :role, Ecto.Enum, values: [:owner, :manager, :cashier, :receiver]
    field :active, :boolean, default: true
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :name, :password, :role])
    |> update_change(:email, &String.downcase(String.trim(&1)))
    |> validate_required([:email, :name, :password, :role])
    |> validate_format(:email, ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/)
    |> validate_length(:email, max: 254)
    |> validate_length(:name, min: 1, max: 100)
    |> validate_length(:password, min: 16, max: 128)
    |> unique_constraint(:email)
  end
end

defmodule RobinahsShop.StaffSession do
  use Ecto.Schema

  schema "staff_sessions" do
    field :token_hash, :string
    belongs_to :staff, RobinahsShop.Staff
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end

defmodule RobinahsShop.Product do
  use Ecto.Schema
  import Ecto.Changeset

  schema "products" do
    field :sku, :string
    field :name, :string
    field :category, :string
    field :price, :integer, default: 0
    field :stock, :integer, default: 0
    field :unit, :string, default: "piece"
    field :image, :string
    field :reorder_level, :integer
    field :active, :boolean, default: true
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(product, attrs) do
    product
    |> cast(attrs, [:sku, :name, :category, :price, :unit, :image, :reorder_level, :active])
    |> update_change(:sku, &String.upcase(String.trim(&1)))
    |> update_change(:image, fn
      "" -> nil
      value -> String.trim(value)
    end)
    |> validate_required([:sku, :name, :category, :price, :unit])
    |> validate_length(:sku, min: 1, max: 80)
    |> validate_length(:name, min: 1, max: 160)
    |> validate_length(:unit, min: 1, max: 40)
    |> validate_inclusion(:category, RobinahsShop.Shop.categories())
    |> validate_number(:price, greater_than_or_equal_to: 0, less_than_or_equal_to: 1_000_000_000)
    |> validate_number(:reorder_level,
      greater_than_or_equal_to: 0,
      less_than_or_equal_to: 1_000_000_000
    )
    |> validate_format(:image, ~r{^/resources/[a-zA-Z0-9_.-]+$})
    |> unique_constraint(:sku)
  end
end

defmodule RobinahsShop.Receiving do
  use Ecto.Schema

  schema "receivings" do
    field :request_id, :string
    field :fingerprint, :string
    field :quantity, :integer
    field :buying_cost, :integer
    field :supplier, :string
    field :reference, :string
    belongs_to :product, RobinahsShop.Product
    belongs_to :staff, RobinahsShop.Staff
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end

defmodule RobinahsShop.Sale do
  use Ecto.Schema

  schema "sales" do
    field :request_id, :string
    field :fingerprint, :string
    field :total, :integer
    field :payment_method, :string
    field :cash_received, :integer
    field :change, :integer
    belongs_to :staff, RobinahsShop.Staff
    has_many :items, RobinahsShop.SaleItem
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end

defmodule RobinahsShop.SaleItem do
  use Ecto.Schema

  schema "sale_items" do
    belongs_to :sale, RobinahsShop.Sale
    belongs_to :product, RobinahsShop.Product
    field :sku, :string
    field :name, :string
    field :quantity, :integer
    field :unit_price, :integer
  end
end

defmodule RobinahsShop.Expense do
  use Ecto.Schema
  import Ecto.Changeset

  @categories [
    "Rent",
    "Utilities",
    "Transport",
    "Wages",
    "Packaging",
    "Licences & fees",
    "Repairs",
    "Other"
  ]

  def categories, do: @categories

  schema "expenses" do
    field :spent_on, :date
    field :category, :string
    field :description, :string
    field :amount, :integer
    belongs_to :staff, RobinahsShop.Staff
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(expense, attrs) do
    expense
    |> cast(attrs, [:spent_on, :category, :description, :amount])
    |> update_change(:description, &String.trim/1)
    |> validate_required([:spent_on, :category, :description, :amount])
    |> validate_length(:description, min: 1, max: 300)
    |> validate_inclusion(:category, @categories)
    |> validate_number(:amount, greater_than: 0, less_than_or_equal_to: 1_000_000_000)
  end
end

defmodule RobinahsShop.StockListEntry do
  use Ecto.Schema
  import Ecto.Changeset

  schema "stock_list_entries" do
    field :number, :integer
    field :item, :string
    field :quantity_as_listed, :string
    field :amount_as_written, :string
    field :needs_name_review, :boolean, default: false
    field :needs_amount_review, :boolean, default: false
    field :notes, :string
    field :status, Ecto.Enum, values: [:pending, :confirmed], default: :pending
    field :confirmed_unit_price, :integer
    field :confirmed_at, :utc_datetime_usec
    belongs_to :product, RobinahsShop.Product
    belongs_to :confirmed_by_staff, RobinahsShop.Staff
    timestamps(type: :utc_datetime_usec)
  end

  def review_changeset(entry, attrs) do
    entry
    |> cast(attrs, [
      :product_id,
      :status,
      :confirmed_unit_price,
      :confirmed_at,
      :confirmed_by_staff_id,
      :notes
    ])
    |> validate_required([:number, :item, :quantity_as_listed, :amount_as_written])
    |> validate_number(:confirmed_unit_price,
      greater_than_or_equal_to: 0,
      less_than_or_equal_to: 1_000_000_000
    )
    |> validate_status_transition()
  end

  defp validate_status_transition(cs) do
    case {get_field(cs, :status), get_change(cs, :status)} do
      {_, :confirmed} ->
        if is_nil(get_change(cs, :confirmed_unit_price)) and
             is_nil(get_field(cs, :confirmed_unit_price)) do
          add_error(cs, :confirmed_unit_price, "must be entered before confirming an entry")
        else
          cs
        end

      _ ->
        cs
    end
  end
end
