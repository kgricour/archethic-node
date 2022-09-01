defmodule ArchethicWeb.DashboardLive do
  @moduledoc """
  Live-View for Network-Metric-Dashboard
  """
  use ArchethicWeb, :live_view

  alias Archethic.Metrics.Poller
  alias ArchethicWeb.DashboardView

  alias Phoenix.View

  def mount(_params, _session, socket) do
    if connected?(socket) do
      send(self(), :monitor)
    end

    version = Application.spec(:archethic, :vsn)

    new_socket = socket |> assign(%{version: version})

    {:ok, new_socket}
  end

  def handle_info(:monitor, socket) do
    Poller.monitor()
    {:noreply, socket}
  end

  def handle_info({:update_data, data}, socket) do
    {:noreply, socket |> push_event("network_points", %{points: data})}
  end

  def render(assigns) do
    View.render(DashboardView, "dashboard.html", assigns)
  end
end
