defmodule Project2Web.CheckoutLive do
  use Phoenix.LiveView
  alias Project2.Carts
  # alias Project2.Payments
  alias Project2.Accounts

  def mount(_params, _session, socket) do
    user_id = socket.assigns.current_user.id

    case Carts.get_cart(user_id) do
      {:ok, cart} ->
        order_items = Carts.list_order_items(cart.id)
        total_price = calculate_total_price(order_items)

        address =
          Accounts.get_user_address(user_id) ||
            %{
              full_name: "",
              phone_number: "",
              shipping_address: "",
              city: "",
              state: "",
              zip_code: ""
            }

        {:ok,
         assign(socket,
           cart: cart,
           order_items: order_items,
           total_price: total_price,
           full_name: address.full_name,
           phone_number: address.phone_number,
           shipping_address: address.shipping_address,
           city: address.city,
           state: address.state,
           zip_code: address.zip_code,
           payment_method: "mpesa"
         )}

      {:error, _reason} ->
        {:ok, assign(socket, cart: nil, order_items: [], total_price: 0)}
    end
  end

  def handle_event(
        "update_address",
        %{
          "full_name" => full_name,
          "phone_number" => phone_number,
          "shipping_address" => shipping,
          "city" => city,
          "state" => state,
          "zip_code" => zip_code
        },
        socket
      ) do
    {:noreply,
     assign(socket,
       full_name: full_name,
       phone_number: phone_number,
       shipping_address: shipping,
       city: city,
       state: state,
       zip_code: zip_code
     )}
  end

  def handle_event("select_payment_method", %{"payment_method" => payment_method}, socket) do
    {:noreply, assign(socket, payment_method: payment_method)}
  end

  def handle_event("place_order", _params, socket) do
    user_id = socket.assigns.current_user.id
    payment_method = socket.assigns.payment_method
    phone_number = socket.assigns.phone_number
    amount = Decimal.to_string(socket.assigns.total_price)

    address_params = %{
      full_name: socket.assigns.full_name,
      phone_number: phone_number,
      shipping_address: socket.assigns.shipping_address,
      city: socket.assigns.city,
      state: socket.assigns.state,
      zip_code: socket.assigns.zip_code,
      user_id: user_id
    }

    case Accounts.save_user_address(user_id, address_params) do
      {:ok, _address} ->
        if phone_number == "" do
          IO.puts("Phone number is required for Mpesa payment.")
          {:noreply, push_event(socket, "phone_number_missing", %{})}
        else
          case payment_method do
            #  "bank_card" ->
            #   case Payments.create_payment_intent(user_id) do
            #    {:ok, client_secret} ->
            #     {:noreply,
            #     push_event(socket, "stripe_checkout", %{client_secret: client_secret})}

            # {:error, reason} ->
            #  IO.inspect(reason, label: "Payment Intent Error")
            #     {:noreply, push_navigate(socket, to: "/checkout")}
            # end

            "mpesa" ->
              case Project2.Payments.Mpesa.lipa_na_mpesa_online(%{
                     phone_number: phone_number,
                     amount: amount,
                     callback_url: "https://be10-41-139-227-122.ngrok-free.app/api/mpesa_callback
                     "
                   }) do
                {:ok, response} ->
                  IO.inspect(response, label: "Mpesa Response")
                  {:noreply, push_event(socket, "payment_processing", %{status: "pending"})}
                  {:noreply, push_navigate(socket, to: "/user_account")}

                {:error, %HTTPoison.Error{reason: reason}} ->
                  IO.inspect(reason, label: "Mpesa HTTPoison Error")
                  {:noreply, push_navigate(socket, to: "/checkout")}

                {:error, error} ->
                  IO.inspect(error, label: "Mpesa Payment Error")
                  {:noreply, push_navigate(socket, to: "/checkout")}
              end
          end
        end

      {:error, reason} ->
        IO.inspect(reason, label: "Address Save Error")
        {:noreply, push_navigate(socket, to: "/checkout")}
    end
  end

  defp calculate_total_price(order_items) do
    Enum.reduce(order_items, Decimal.new("0"), fn item, acc ->
      Decimal.add(acc, Decimal.mult(item.product.price, item.quantity))
    end)
  end

  def render(assigns) do
    ~H"""
    <div class="checkout-container mx-auto max-w-4xl p-6" style="background:aliceblue;">
      <h2 class="text-3xl font-bold text-center text-green-700 mb-6">Checkout</h2>

      <div class="grid grid-cols-1 md:grid-cols-2 gap-6 mb-6">
        <div class="checkout-section bg-white p-6 border rounded shadow">
          <h3 class="text-xl font-semibold mb-4">Shipping Information</h3>
          <form phx-change="update_address">
            <input
              type="text"
              name="full_name"
              value={@full_name}
              class="w-full p-3 border border-gray-300 rounded mb-4"
              placeholder="Full Name"
            />
            <input
              type="text"
              name="phone_number"
              value={@phone_number}
              class="w-full p-3 border border-gray-300 rounded mb-4"
              placeholder="Phone Number"
            />
            <input
              type="text"
              name="shipping_address"
              value={@shipping_address}
              class="w-full p-3 border border-gray-300 rounded mb-4"
              placeholder="Shipping Address"
            />
            <input
              type="text"
              name="city"
              value={@city}
              class="w-full p-3 border border-gray-300 rounded mb-4"
              placeholder="City"
            />
            <input
              type="text"
              name="state"
              value={@state}
              class="w-full p-3 border border-gray-300 rounded mb-4"
              placeholder="County"
            />
            <input
              type="text"
              name="zip_code"
              value={@zip_code}
              class="w-full p-3 border border-gray-300 rounded"
              placeholder="Zip Code"
            />
          </form>
        </div>

        <div class="checkout-section bg-white p-6 border rounded shadow">
          <h3 class="text-xl font-semibold mb-4">Order Summary</h3>
          <ul class="space-y-4">
            <%= for item <- @order_items do %>
              <li class="flex items-center space-x-4 bg-gray-100 p-4 border rounded">
                <img
                  src={item.product.image_url}
                  alt={item.product.name}
                  class="w-24 h-24 object-cover"
                />
                <div class="flex-1">
                  <h4 class="text-lg font-semibold"><%= item.product.name %></h4>
                  <p class="text-gray-700">Quantity: <%= item.quantity %></p>
                  <p class="text-green-600">Price: <%= item.product.price %></p>
                </div>
              </li>
            <% end %>
          </ul>
          <p class="text-xl font-semibold mt-4">Total Price: <%= @total_price %></p>
        </div>
      </div>

      <div class="checkout-section bg-white p-6 border rounded shadow mb-6">
        <h3 class="text-xl font-semibold mb-4">Payment Method</h3>
        <select
          phx-change="select_payment_method"
          name="payment_method"
          class="w-full p-3 border border-gray-300 rounded"
        >
          <option value="bank_card">Bank Card</option>
          <option value="paypal">PayPal</option>
          <option value="mpesa" selected>Mpesa</option>
        </select>
      </div>

      <div class="text-center">
        <button
          phx-click="place_order"
          class="bg-green-500 text-white py-3 px-6 rounded shadow hover:bg-green-600 transition"
        >
          Place Order
        </button>
      </div>
    </div>
    """
  end
end
