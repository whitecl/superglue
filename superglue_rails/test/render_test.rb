require 'test_helper'

class RenderController < TestController
  require 'action_view/testing/resolvers'

  append_view_path(ActionView::FixtureResolver.new(
    'render/simple_render_with_superglue.json.props' => 'json.author "john smith"',
    'render/simple_render_with_superglue_with_bad_layout.json.props' => 'json.author "john smith"',
    'layouts/application.json.props' => 'json.data {yield json}',
    'layouts/does_not_exist.html.erb' => '',
    'layouts/application.html.erb' => <<~HTML
      <html>
        <head>
          <script><%= @initial_state.strip.html_safe %></script>
        </head>
        <body><%=yield%></body>
      </html>
    HTML
  ))

  layout 'application'

  def render_action
    render :action
  end

  def simple_render_with_superglue
    @initial_state = render_to_string(formats: [:json], layout: true)
    render inline: '', layout: true
  end

  def simple_render_with_superglue_with_bad_layout
    @initial_state = render_to_string(formats: [:json], layout: 'does_not_exist')
    render inline: '', layout: true
  end

  def form_authenticity_token
    "secret"
  end
end

class RenderTest < ActionController::TestCase
  tests RenderController


  setup do
    if Rails.version >= '6'
      # In rails 6, the fixture orders the templates based on their appearance in the handler
      # This doesn't happen IRL, so I'm going to explicitly set the handler here.
      #
      # Note that the original is the following
      # @controller.lookup_context.handlers = [:raw, :superglue, :erb, :js, :html, :builder, :ruby]
      @controller.lookup_context.handlers = [:props, :erb]
    end
  end

  test "simple render with superglue" do
    get :simple_render_with_superglue

    assert_response 200
    rendered = <<~HTML
      <html>
        <head>
          <script>{"data":{"author":"john smith"}}</script>
        </head>
        <body></body>
      </html>
    HTML

    assert_equal rendered, @response.body
    assert_equal 'text/html', @response.media_type
  end

  test "simple render when the layout doesn't exist" do
    err = assert_raise ActionView::MissingTemplate do |e|
      get :simple_render_with_superglue_with_bad_layout
    end

    assert_equal(true, err.message.starts_with?('Missing template layouts/does_not_exist with {:locale=>[:en], :formats=>[:json], :variants=>[], :handlers=>[:props, :erb]}.'))
  end
end
