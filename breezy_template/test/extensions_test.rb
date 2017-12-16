require "test_helper"
require "mocha"

require "action_view"
require "action_view/testing/resolvers"
require "breezy_template"
require 'byebug'
require 'mocha/test_unit'

BLOG_POST_PARTIAL = <<-JBUILDER
  json.extract! blog_post, :id, :body
  json.author do
    first_name, last_name = blog_post.author_name.split(nil, 2)
    json.first_name first_name
    json.last_name last_name
  end
JBUILDER

COLLECTION_PARTIAL = <<-JBUILDER
  json.extract! collection, :id, :name
JBUILDER

PROFILE_PARTIAL = <<-JBUILDER
  json.email email
JBUILDER

FOOTER_PARTIAL = <<-JBUILDER
  json.terms "You agree"
JBUILDER

BlogPost = Struct.new(:id, :body, :author_name)
Collection = Struct.new(:id, :name)
blog_authors = [ "David Heinemeier Hansson", "Pavel Pravosud" ].cycle
BLOG_POST_COLLECTION = Array.new(10){ |i| BlogPost.new(i+1, "post body #{i+1}", blog_authors.next) }
COLLECTION_COLLECTION = Array.new(5){ |i| Collection.new(i+1, "collection #{i+1}") }

ActionView::Template.register_template_handler :breezy, BreezyTemplate::Handler

PARTIALS = {
  "_partial.js.breezy"  => "foo ||= 'hello'; json.content foo",
  "_blog_post.js.breezy" => BLOG_POST_PARTIAL,
  "_profile.js.breezy" => PROFILE_PARTIAL,
  "_footer.js.breezy" => FOOTER_PARTIAL,
  "_collection.js.breezy" => COLLECTION_PARTIAL
}

def strip_format(str)
  str.strip_heredoc.gsub(/\n\s*/, "")
end

class BreezyTemplateTest < ActionView::TestCase
  setup do
    self.request_forgery = false
    BreezyTemplate.configuration.track_assets = []

    # this is a stub. Normally this would be set by the
    # controller locals
    self.breezy = {}

    @context = self
    Rails.cache.clear
  end

  teardown do
    # Mocha didn't auto teardown??
    Mocha::Mockery.teardown
  end

  cattr_accessor :request_forgery, :breezy
  self.request_forgery = false

  def breezy_filter
    @breezy_filter
  end

  def request
    @request
  end

  # Stub out a couple of methods that'll get called from cache_fragment_name
  def view_cache_dependencies
    []
  end

  def jbuild(source, opts={})
    @breezy_filter = opts[:breezy_filter]
    @request = opts[:request] || action_controller_test_request
    @rendered = []
    partials = PARTIALS.clone
    partials["test.js.breezy"] = source
    resolver = ActionView::FixtureResolver.new(partials)
    lookup_context.view_paths = [resolver]
    lookup_context.formats = [:js]
    template = ActionView::Template.new(source, "test", BreezyTemplate::Handler, virtual_path: "test")
    template.render(self, {}).strip
  end

  def action_controller_test_request
    if ::Rails.version.start_with?('5')
      ::ActionController::TestRequest.create
    else
      ::ActionController::TestRequest.new
    end
  end

  def cache_keys
    major_v = Rails::VERSION::MAJOR
    minor_v = Rails::VERSION::MINOR
    rails_v = "rails#{major_v}#{minor_v}"
    path = File.expand_path("../fixtures/cache_keys.yaml", __FILE__)
    keys = YAML.load_file(path)
    keys[method_name][rails_v]
  end

  def undef_context_methods(*names)
    self.class_eval do
      names.each do |name|
        undef_method name.to_sym if method_defined?(name.to_sym)
      end
    end
  end

  def protect_against_forgery?
    self.request_forgery
  end

  def form_authenticity_token
    "secret"
  end

  test "rendering" do
    result = jbuild(<<-JBUILDER)
      json.content "hello"
    JBUILDER

    expected = strip_format(<<-JS)
      (function(){
        var joints={};
        var cache={};
        var defers=[];
        return ({"data":{"content":"hello"},"joints":joints,"defers":defers});
      })()
    JS

    assert_equal expected, result
  end

  test "when rendering with duplicate keys, the last one wins" do
    result = jbuild(<<-JBUILDER)
      json.content do
        json.miss 123
      end

      json.content do
        json.hit 123
      end
    JBUILDER


    expected = strip_format(<<-JS)
      (function(){
        var joints={};
        var cache={};
        var defers=[];
        return ({"data":{"content":{"hit":123}},"joints":joints,"defers":defers});
      })()
    JS

    assert_equal expected, result
  end

  test "when rendering with duplicate array values, the last one wins" do
    result = jbuild(<<-JBUILDER)
      json.content do
        json.array! [1,2]
        json.array! [3,4]
      end
    JBUILDER

    expected = strip_format(<<-JS)
      (function(){
        var joints={};
        var cache={};
        var defers=[];
        return ({\"data\":{\"content\":[3,4]},"joints":joints,"defers":defers});
      })()
    JS

    assert_equal expected, result
  end
  #
  test "render with asset tracking" do
    BreezyTemplate.configuration.track_assets = ['test.js', 'test.css']

    result = jbuild(<<-TEMPLATE)
      json.content "hello"
    TEMPLATE

    expected = strip_format(<<-JS)
      (function(){
        var joints={};
        var cache={};
        var defers=[];
        return ({"data":{"content":"hello"},"assets":["/test.js","/test.css"],"joints":joints,"defers":defers});
      })()
    JS

    assert_equal expected, result
  end


  test "render with csrf token when request forgery is on" do
    self.request_forgery = true
    # csrf_meta_tags also delegate authenticity tokens to the controller
    # here we provide a simple mock to the context

    result = jbuild(<<-TEMPLATE)
      json.content "hello"
    TEMPLATE

    expected = strip_format(<<-JS)
      (function(){
        var joints={};
        var cache={};
        var defers=[];
        return ({"data":{"content":"hello"},"csrf_token":"secret","joints":joints,"defers":defers});
      })()
    JS

    assert_equal expected, result
  end

  test "wrapping jbuilder contents inside Breezy with additional options" do
    BreezyTemplate.configuration.track_assets = ['test.js', 'test.css']
    self.breezy = { title: 'this is fun' }

    result = jbuild(<<-TEMPLATE)
      json.content "hello"
    TEMPLATE

    expected = strip_format(<<-JS)
      (function(){
        var joints={};
        var cache={};
        var defers=[];
        return ({"data":{"content":"hello"},"title":"this is fun","assets":["/test.js","/test.css"],"joints":joints,"defers":defers});
      })()
    JS

    assert_equal expected, result
  end

  test "key_format! with parameter" do
    result = jbuild(<<-JBUILDER)
      json.key_format! camelize: [:lower]
      json.camel_style "for JS"
    JBUILDER

    expected = strip_format(<<-JS)
      (function(){
        var joints={};
        var cache={};
        var defers=[];
        return ({"data":{"camelStyle":"for JS"},"joints":joints,"defers":defers});
      })()
    JS

    assert_equal expected, result
  end

  test "key_format! propagates to child elements" do
    result = jbuild(<<-JBUILDER)
      json.key_format! :upcase
      json.level1 "one"
      json.level2 do
        json.value "two"
      end
    JBUILDER

    expected = strip_format(<<-JS)
      (function(){
        var joints={};
        var cache={};
        var defers=[];
        return ({"data":{
          "LEVEL1":"one",
          "LEVEL2":{"VALUE":"two"}
        },"joints":joints,"defers":defers});
      })()
    JS

    assert_equal expected, result
  end

  test "renders partial via the option through set!" do
    @post = BLOG_POST_COLLECTION.first
    Rails.cache.clear

    result = jbuild(<<-JBUILDER)
      json.post @post, partial: ["blog_post", as: :blog_post, joint: :header]
    JBUILDER

    expected = strip_format(<<-JS)
      (function(){
        var joints={};
        var cache={};
        var defers=[];
        joints['header'] ||= []; joints['header'].push('post');
        return ({"data":{"post":{
          "id":1,
          "body":"post body 1",
          "author":{"first_name":"David","last_name":"Heinemeier Hansson"}
        }},"joints":joints,"defers":defers});
      })()
    JS

    assert_equal expected, result
  end

  test "renders a partial with no locals" do
    result = jbuild(<<-JBUILDER)
      json.footer nil, partial: "footer"
    JBUILDER

    expected = strip_format(<<-JS)
      (function(){
        var joints={};
        var cache={};
        var defers=[];
        return ({"data":{"footer":{"terms":"You agree"}},"joints":joints,"defers":defers});
      })()
    JS
    assert_equal expected, result
  end

  test "renders a partial with locals" do
    result = jbuild(<<-JBUILDER)
      json.profile nil, partial: ["profile", locals: {email: "test@test.com"}]
    JBUILDER

    expected = strip_format(<<-JS)
      (function(){
        var joints={};
        var cache={};
        var defers=[];
        return ({"data":{"profile":{"email":"test@test.com"}},"joints":joints,"defers":defers});
      })()
    JS
    assert_equal expected, result
  end

  test "renders a partial with locals and caches" do
    result = jbuild(<<-JBUILDER)
      opts = {
        cache: 'cachekey',
        partial: ["profile", locals: {email: "test@test.com"}]
      }
      json.profile 32, opts
    JBUILDER

    expected = strip_format(<<-JS)
      (function(){
        var joints={};
        var cache={};
        var defers=[];
        cache["#{cache_keys[0]}"]={"email":"test@test.com"};
        return ({"data":{"profile":cache["#{cache_keys[0]}"]},"joints":joints,"defers":defers});
      })()
    JS

    assert_equal expected, result
  end

  test "renders a partial even without a :as to the value, this usage is rare" do
    result = jbuild(<<-JBUILDER)
      json.profile 32, partial: ["profile", locals: {email: "test@test.com"}]
    JBUILDER

    expected = strip_format(<<-JS)
      (function(){
        var joints={};
        var cache={};
        var defers=[];
        return ({"data":{"profile":{"email":"test@test.com"}},"joints":joints,"defers":defers});
      })()
    JS

    assert_equal expected, result
  end

  test "render array of partials without an :as to a member, this usage is very rare" do
    result = jbuild(<<-JBUILDER)
      json.array! [1,2], partial: "footer"
    JBUILDER

    expected = strip_format(<<-JS)
      (function(){
        var joints={};
        var cache={};
        var defers=[];
        return ({"data":[{"terms":"You agree"},{"terms":"You agree"}],"joints":joints,"defers":defers});
      })()
    JS

    assert_equal expected, result
  end

  test "render array of partials without an :as to a member and cache" do
    result = jbuild(<<-JBUILDER)
      json.array! [1,2], partial: "footer", cache: ->(i){ ['a', i] }
    JBUILDER

    expected = strip_format(<<-JS)
      (function(){
        var joints={};
        var cache={};
        var defers=[];
        cache["#{cache_keys[0]}"]={"terms":"You agree"};
        cache["#{cache_keys[1]}"]={"terms":"You agree"};
        return ({"data":[cache["#{cache_keys[0]}"],cache["#{cache_keys[1]}"]],"joints":joints,"defers":defers});
      })()
    JS

    assert_equal expected, result
  end

  test "render array of partials" do
    result = jbuild(<<-JBUILDER)
      json.array! BLOG_POST_COLLECTION, partial: ["blog_post", as: :blog_post]
    JBUILDER

    expected = strip_format(<<-JS)
      (function(){
        var joints={};
        var cache={};
        var defers=[];
        return ({"data":[
          {"id":1,"body":"post body 1","author":{"first_name":"David","last_name":"Heinemeier Hansson"}},
          {"id":2,"body":"post body 2","author":{"first_name":"Pavel","last_name":"Pravosud"}},
          {"id":3,"body":"post body 3","author":{"first_name":"David","last_name":"Heinemeier Hansson"}},
          {"id":4,"body":"post body 4","author":{"first_name":"Pavel","last_name":"Pravosud"}},
          {"id":5,"body":"post body 5","author":{"first_name":"David","last_name":"Heinemeier Hansson"}},
          {"id":6,"body":"post body 6","author":{"first_name":"Pavel","last_name":"Pravosud"}},
          {"id":7,"body":"post body 7","author":{"first_name":"David","last_name":"Heinemeier Hansson"}},
          {"id":8,"body":"post body 8","author":{"first_name":"Pavel","last_name":"Pravosud"}},
          {"id":9,"body":"post body 9","author":{"first_name":"David","last_name":"Heinemeier Hansson"}},
          {"id":10,"body":"post body 10","author":{"first_name":"Pavel","last_name":"Pravosud"}}
        ],"joints":joints,"defers":defers});
      })()
    JS

    assert_equal expected, result
  end

  test "renders array of partials as empty array with nil-collection" do
    result = jbuild(<<-JBUILDER)
      json.array! nil, partial: ["blog_post", as: :blog_post]
    JBUILDER

    expected = strip_format(<<-JS)
      (function(){
        var joints={};
        var cache={};
        var defers=[];
        return ({"data":[],"joints":joints,"defers":defers});
      })()
    JS

    assert_equal expected, result
  end

  test "renders the partial and ignores the value" do
    result = jbuild <<-JBUILDER
      json.posts nil, partial: "footer"
    JBUILDER

    expected = strip_format(<<-JS)
      (function(){
        var joints={};
        var cache={};
        var defers=[];
        return ({"data":{"posts":{"terms":"You agree"}},"joints":joints,"defers":defers});
      })()
    JS
    assert_equal expected, result
  end

  test "caching a value at a node" do
    undef_context_methods :fragment_name_with_digest, :cache_fragment_name

    result = jbuild(<<-JBUILDER)
      opts = {
        cache: [['b', 'c']]
      }
      json.hello 32, opts
    JBUILDER

    expected = strip_format(<<-JS)
      (function(){
        var joints={};
        var cache={};
        var defers=[];
        cache["#{cache_keys[0]}"]=32;
        return ({"data":{"hello":cache["#{cache_keys[0]}"]},"joints":joints,"defers":defers});
      })()
    JS

    assert_equal expected, result
  end

  test "caching elements in a list" do
    undef_context_methods :fragment_name_with_digest, :cache_fragment_name

    result = jbuild(<<-JBUILDER)
      json.hello do
        opts = {
          cache: ->(i){ ['a', i] }
        }
        json.array! [4,5], opts do |x|
          json.top "hello" + x.to_s
        end
      end
    JBUILDER

    expected = strip_format(<<-JS)
      (function(){
        var joints={};
        var cache={};
        var defers=[];
        cache["#{cache_keys[0]}"]={"top":"hello4"};
        cache["#{cache_keys[1]}"]={"top":"hello5"};
        return ({"data":{"hello":[cache["#{cache_keys[0]}"],cache["#{cache_keys[1]}"]]},"joints":joints,"defers":defers});
      })()
    JS

    assert_equal expected, result
  end

  test "nested caching generates a depth-first list of cache nodes" do
    undef_context_methods :fragment_name_with_digest, :cache_fragment_name

    result = jbuild(<<-JBUILDER)
      json.hello cache: [['a', 'b']] do
        json.content cache: [['d', 'z']] do
          json.subcontent 'inner'
        end
        json.other cache: [['e', 'z']] do
          json.subcontent 'other'
        end
      end
    JBUILDER

    expected = strip_format(<<-JS)
      (function(){
        var joints={};
        var cache={};
        var defers=[];
        cache["#{cache_keys[0]}"]={"subcontent":"inner"};
        cache["#{cache_keys[1]}"]={"subcontent":"other"};
        cache["#{cache_keys[2]}"]={"content":cache["#{cache_keys[0]}"],"other":cache["#{cache_keys[1]}"]};
        return ({"data":{"hello":cache["#{cache_keys[2]}"]},"joints":joints,"defers":defers});
      })()
    JS

    assert_equal expected, result
  end

  test "caching an empty block generates no cache and no errors" do
    undef_context_methods :fragment_name_with_digest, :cache_fragment_name

    result = nil

    assert_nothing_raised do
        result = jbuild(<<-JBUILDER)
          json.hello do
            json.array! [4,5], cache: ->(i){['a', i]} do |x|
            end
          end
        JBUILDER
    end

    expected = strip_format(<<-JS)
      (function(){
        var joints={};
        var cache={};
        var defers=[];
        return ({\"data\":{\"hello\":[]},"joints":joints,"defers":defers});
      })()
    JS

    assert_equal expected, result
  end
  #
  # test "child! accepts cache options" do
  #   undef_context_methods :fragment_name_with_digest, :cache_fragment_name
  #
  #   result = jbuild(<<-JBUILDER)
  #     json.comments do
  #       json.child!(cache: ['e', 'z']) { json.content "hello" }
  #       json.child! { json.content "world" }
  #     end
  #   JBUILDER
  #
  #   expected = strip_format(<<-JS)
  #     (function(){
  #       cache["#{cache_keys[0]}", {"content":"hello"});
  #       return ({"data":{"comments":[cache["#{cache_keys[0]}"),{"content":"world"}]}});
  #     })()
  #   JS
  #
  #   assert_equal expected, result
  # end

  test "fragment caching" do
    undef_context_methods :fragment_name_with_digest, :cache_fragment_name

    jbuild(<<-JBUILDER)
      opts = {cache: ['cachekey']}
      json.post opts do
        json.name "Cache"
      end
    JBUILDER

    result = jbuild(<<-JBUILDER)
      opts = {cache: ['cachekey']}
      json.post opts do
        json.name "Miss"
      end
    JBUILDER

    expected = strip_format(<<-JS)
      (function(){
        var joints={};
        var cache={};
        var defers=[];
        cache["#{cache_keys[0]}"]={"name":"Cache"};
        return ({"data":{"post":cache["#{cache_keys[0]}"]},"joints":joints,"defers":defers});
      })()
    JS

    assert_equal expected, result
  end

  test "fragment caching deserializes an array" do
    undef_context_methods :fragment_name_with_digest, :cache_fragment_name

    result = jbuild <<-JBUILDER
      json.content cache: "cachekey" do
        json.array! %w[a b c]
      end
    JBUILDER

    expected = strip_format(<<-JS)
      (function(){
        var joints={};
        var cache={};
        var defers=[];
        cache["#{cache_keys[0]}"]=["a","b","c"];
        return ({"data":{"content":cache["#{cache_keys[0]}"]},"joints":joints,"defers":defers});
      })()
    JS

    assert_equal expected, result
  end
  #
  test "fragment caching works with previous version of cache digests" do
    undef_context_methods :cache_fragment_name

    if !@context.class.method_defined? :fragment_name_with_digest
      @context.class_eval do
        def fragment_name_with_digest
        end
      end
    end

    @context.expects :fragment_name_with_digest

    jbuild <<-JBUILDER
      json.content cache: 'cachekey' do
        json.name "Cache"
      end
    JBUILDER
  end

  test "fragment caching works with current cache digests" do
    undef_context_methods :fragment_name_with_digest

    @context.expects :cache_fragment_name
    ActiveSupport::Cache.expects :expand_cache_key

    jbuild <<-JBUILDER
      json.content cache: 'cachekey' do
        json.name "Cache"
      end
    JBUILDER
  end

  # test "current cache digest option accepts options through the last element hash" do
  #   undef_context_methods :fragment_name_with_digest
  #
  #   @context.expects(:cache_fragment_name)
  #     .with("cachekey", skip_digest: true)
  #     .returns("cachekey")
  #
  #   ActiveSupport::Cache.expects :expand_cache_key
  #
  #   jbuild <<-JBUILDER
  #     json.wrap! :cache, 'cachekey', skip_digest: true
  #     json.content do
  #       json.name "Cache"
  #     end
  #   JBUILDER
  # end

  test "does not perform caching when controller.perform_caching is false" do
    controller.perform_caching = false

    result = jbuild <<-JBUILDER
      json.content cache: 'cachekey' do
        json.name "Cache"
      end
    JBUILDER

    expected = strip_format(<<-JS)
      (function(){
        var joints={};
        var cache={};
        var defers=[];
        return ({"data":{"content":{"name":"Cache"}},"joints":joints,"defers":defers});
      })()
    JS

    assert_equal expected, result
  end

  test "invokes templates via params via set! and caches" do
    @post = BLOG_POST_COLLECTION.first

    result = jbuild(<<-JBUILDER)
      json.post @post, partial: ["blog_post", as: :blog_post], cache: [['a', 'b']]
    JBUILDER

    expected = strip_format(<<-JS)
      (function(){
        var joints={};
        var cache={};
        var defers=[];
        cache["#{cache_keys[0]}"]={"id":1,"body":"post body 1","author":{"first_name":"David","last_name":"Heinemeier Hansson"}};
        return ({"data":{"post":cache["#{cache_keys[0]}"]},"joints":joints,"defers":defers});
      })()
    JS

    assert_equal expected, result
  end

  test "shares partial caches (via the partial's digest) across multiple templates" do
    undef_context_methods :fragment_name_with_digest, :cache_fragment_name

    @hit = BlogPost.new(1, "hit", "John Smith")
    @miss = BlogPost.new(2, "miss", "John Smith")

    cat =  jbuild(<<-JBUILDER)
      opts = {
        cache: [['a', 'b']],
        partial: ["blog_post", as: :blog_post]
      }

      json.post @hit, opts
    JBUILDER

    result = jbuild(<<-JBUILDER)
      opts = {
        cache: [['a', 'b']],
        partial: ["blog_post", as: :blog_post]
      }

      json.post @miss, opts
    JBUILDER

    expected = strip_format(<<-JS)
      (function(){
        var joints={};
        var cache={};
        var defers=[];
        cache["#{cache_keys[0]}"]={"id":1,"body":"hit","author":{"first_name":"John","last_name":"Smith"}};
        return ({"data":{"post":cache["#{cache_keys[0]}"]},"joints":joints,"defers":defers});
      })()
    JS

    assert_equal expected, result
  end


  test "render array of partials and caches" do
    result = jbuild(<<-JBUILDER)
      opts = {
        cache: (->(d){ ['a', d.id] }),
        partial: ["blog_post", as: :blog_post]
      }
      json.array! BLOG_POST_COLLECTION, opts
    JBUILDER
    Rails.cache.clear

    expected = strip_format(<<-JS)
      (function(){
        var joints={};
        var cache={};
        var defers=[];
        cache["#{cache_keys[0]}"]={"id":1,"body":"post body 1","author":{"first_name":"David","last_name":"Heinemeier Hansson"}};
        cache["#{cache_keys[1]}"]={"id":2,"body":"post body 2","author":{"first_name":"Pavel","last_name":"Pravosud"}};
        cache["#{cache_keys[2]}"]={"id":3,"body":"post body 3","author":{"first_name":"David","last_name":"Heinemeier Hansson"}};
        cache["#{cache_keys[3]}"]={"id":4,"body":"post body 4","author":{"first_name":"Pavel","last_name":"Pravosud"}};
        cache["#{cache_keys[4]}"]={"id":5,"body":"post body 5","author":{"first_name":"David","last_name":"Heinemeier Hansson"}};
        cache["#{cache_keys[5]}"]={"id":6,"body":"post body 6","author":{"first_name":"Pavel","last_name":"Pravosud"}};
        cache["#{cache_keys[6]}"]={"id":7,"body":"post body 7","author":{"first_name":"David","last_name":"Heinemeier Hansson"}};
        cache["#{cache_keys[7]}"]={"id":8,"body":"post body 8","author":{"first_name":"Pavel","last_name":"Pravosud"}};
        cache["#{cache_keys[8]}"]={"id":9,"body":"post body 9","author":{"first_name":"David","last_name":"Heinemeier Hansson"}};
        cache["#{cache_keys[9]}"]={"id":10,"body":"post body 10","author":{"first_name":"Pavel","last_name":"Pravosud"}};
        return ({"data":[cache["#{cache_keys[0]}"],cache["#{cache_keys[1]}"],cache["#{cache_keys[2]}"],cache["#{cache_keys[3]}"],cache["#{cache_keys[4]}"],cache["#{cache_keys[5]}"],cache["#{cache_keys[6]}"],cache["#{cache_keys[7]}"],cache["#{cache_keys[8]}"],cache["#{cache_keys[9]}"]],"joints":joints,"defers":defers});
      })()
    JS
    assert_equal expected, result
  end

  test "filtering for a node in the tree" do
    result = jbuild(<<-JBUILDER)
      json._filter_by_path('hit.hit2')
      json.hit do
        json.hit2 do
          json.greeting 'hello world'
        end
      end

      json.miss do
        json.miss2 do
          raise 'this should not be called'
          json.greeting 'missed call'
        end
      end
    JBUILDER
    Rails.cache.clear

    expected = strip_format(<<-JS)
      (function(){
        var joints={};
        var cache={};
        var defers=[];
        return (
          {"data":{"greeting":"hello world"},"joints":joints,"defers":defers}
        );
      })()
    JS

    assert_equal expected, result
  end

  test "filtering for a raw value is also possble" do
    result = jbuild(<<-JBUILDER, breezy_filter: 'hit.hit2')
      json.hit do
        json.hit2 23
      end

      json.miss do
        json.miss2 do
          raise 'this should not be called'
          json.greeting 'missed call'
        end
      end
    JBUILDER
    Rails.cache.clear

    expected = strip_format(<<-JS)
      (function(){
        var joints={};
        var cache={};
        var defers=[];
        return (
          {"data":23,"action":"graft","path":"hit.hit2","joints":joints,"defers":defers}
        );
      })()
    JS

    assert_equal expected, result
  end

  test "filter with partial" do
    result = jbuild(<<-JBUILDER, breezy_filter: 'hit.hit2.terms')
      json.hit do
        json.hit2 nil, partial: "footer"
      end
    JBUILDER

    expected = strip_format(<<-JS)
      (function(){
        var joints={};
        var cache={};
        var defers=[];
        return (
          {"data":"You agree","action":"graft","path":"hit.hit2.terms","joints":joints,"defers":defers}
        );
      })()
    JS
    assert_equal expected, result
  end

  test "filtering for a node in the tree via breezy_filter helper" do
    result = jbuild(<<-JBUILDER, breezy_filter: 'hit.hit2')
      json.hit do
        json.hit2 do
          json.greeting 'hello world'
        end
      end

      json.miss do
        json.miss2 do
          raise 'this should not be called'
          json.greeting 'missed call'
        end
      end
    JBUILDER
    Rails.cache.clear

    expected = strip_format(<<-JS)
      (function(){
        var joints={};
        var cache={};
        var defers=[];
        return (
          {"data":{"greeting":"hello world"},"action":"graft","path":"hit.hit2","joints":joints,"defers":defers}
        );
      })()
    JS

    assert_equal expected, result
  end

  test "filtering a cached node returns just that" do
    undef_context_methods :fragment_name_with_digest, :cache_fragment_name
    result = jbuild(<<-JBUILDER, breezy_filter: 'hit.hit2')
      json.hit do
        json.hit2 cache: 'a' do
          json.greeting 'hello world'
        end
      end
    JBUILDER
    Rails.cache.clear

    expected = strip_format(<<-JS)
      (function(){
        var joints={};
        var cache={};
        var defers=[];
        cache["#{cache_keys[0]}"]={"greeting":"hello world"};
        return ({"data":cache["219dfba9f552f91402a22cf67c633582"],"action":"graft","path":"hit.hit2","joints":joints,"defers":defers});
      })()


    JS

    assert_equal expected, result
  end

  test "filtering for a node of a AR relation in a tree by id via an appended where clause" do
    result = jbuild(<<-JBUILDER, breezy_filter: 'hit.hit2.id=1')
      post = Post.create
      post.notes.create title: 'first'
      post.notes.create title: 'second'

      post.notes.expects(:where).once().with('id'=>1).returns([{id: 1, title: 'first'}])

      json.hit do
        json.hit2 do
          json.array! post.notes do |x|
            raise 'this should be be called' if x[:title] == 'second'
            json.title x[:title]
          end
        end
      end
    JBUILDER

    Rails.cache.clear

    expected = strip_format(<<-JS)
      (function(){
        var joints={};
        var cache={};
        var defers=[];
        return (
          {"data":{"title":"first"},"action":"graft","path":"hit.hit2.id=1","joints":joints,"defers":defers}
        );
      })()
    JS
    assert_equal expected, result
  end


  test "filtering for a node of a AR relation in a tree by index via an appended where clause" do
    result = jbuild(<<-JBUILDER, breezy_filter: 'hit.hit2.0')
      post = Post.create
      post.notes.create title: 'first'
      post.notes.create title: 'second'

      offset = post.notes.offset(0)
      post.notes.expects(:offset).once().with(0).returns(offset)

      json.hit do
        json.hit2 do
          json.array! post.notes do |x|
            raise 'this should be be called' if x[:title] == 'second'
            json.title x[:title]
          end
        end
      end
    JBUILDER

    Rails.cache.clear

    expected = strip_format(<<-JS)
      (function(){
        var joints={};
        var cache={};
        var defers=[];
        return (
          {"data":{"title":"first"},"action":"graft","path":"hit.hit2.0","joints":joints,"defers":defers}
        );
      })()
    JS
    assert_equal expected, result
  end

  test "filtering for a node in an array of a tree by id" do
    result = jbuild(<<-JBUILDER, breezy_filter: 'hit.hit2.id=1')
      json.hit do
        json.hit2 do
          json.array! [{id: 1, name: 'hit' }, {id:2, name: 'miss'}] do |x|
            raise 'this should be be called' if x[:name] == 'miss'
            json.name x[:name]
          end
        end
      end
    JBUILDER
    Rails.cache.clear

    expected = strip_format(<<-JS)
      (function(){
        var joints={};
        var cache={};
        var defers=[];
        return (
          {"data":{"name":"hit"},"action":"graft","path":"hit.hit2.id=1","joints":joints,"defers":defers}
        );
      })()
    JS

    assert_equal expected, result
  end

  test "filtering for a node in an array of a tree by index" do
    result = jbuild(<<-JBUILDER, breezy_filter: 'hit.hit2.0')
      json.hit do
        json.hit2 do
          json.array! [{id: 1, name: 'hit' }, {id:2, name: 'miss'}] do |x|
            raise 'this should be be called' if x[:name] == 'miss'
            json.name x[:name]
          end
        end
      end
    JBUILDER
    Rails.cache.clear

    expected = strip_format(<<-JS)
      (function(){
        var joints={};
        var cache={};
        var defers=[];
        return (
          {"data":{"name":"hit"},"action":"graft","path":"hit.hit2.0","joints":joints,"defers":defers}
        );
      })()
    JS

    assert_equal expected, result
  end

  test "rendering with node deferement" do
    req = action_controller_test_request
    req.path = '/some_url'

    result = jbuild(<<-JBUILDER, request: req)
      json.hit do
        json.hit2(defer: :auto)do
          json.hit3 do
            json.greeting 'hello world'
          end
        end
      end
    JBUILDER
    Rails.cache.clear

    expected = strip_format(<<-JS)
      (function(){
        var joints={};
        var cache={};
        var defers=[];
        defers.push({url:'/some_url?_breezy_filter=hit.hit2'});
        return (
          {"data":{"hit":{"hit2":null}},"joints":joints,"defers":defers}
        );
      })()
    JS

    assert_equal expected, result
  end

  test "rendering with manual node deferement" do
    req = action_controller_test_request
    req.path = '/some_url'

    result = jbuild(<<-JBUILDER, request: req)
      json.hit do
        json.hit2 defer: :manual do
          json.hit3 do
            json.greeting 'hello world'
          end
        end
      end
    JBUILDER
    Rails.cache.clear

    expected = strip_format(<<-JS)
      (function(){
        var joints={};
        var cache={};
        var defers=[];
        return (
          {"data":{"hit":{"hit2":null}},"joints":joints,"defers":defers}
        );
      })()
    JS

    assert_equal expected, result
  end

  test "rendering with node array deferment" do
    req = action_controller_test_request
    req.path = '/some_url'

    result = jbuild(<<-JBUILDER, request: req)
      json.hit do
        json.hit2 do
          data = [{id: 1, name: 'foo'}, {id: 2, name: 'bar'}]
          json.array! data, key: :id do
            json.greeting defer: :auto do
              json.gree 'hi'
            end
          end
        end
      end
    JBUILDER
    Rails.cache.clear

    expected = strip_format(<<-JS)
      (function(){
        var joints={};
        var cache={};
        var defers=[];
        defers.push({url:'/some_url?_breezy_filter=hit.hit2.id%3D1.greeting'});
        defers.push({url:'/some_url?_breezy_filter=hit.hit2.id%3D2.greeting'});
        return (
          {"data":{"hit":{"hit2":[{"greeting":null},{"greeting":null}]}},"joints":joints,"defers":defers}
        );
      })()
    JS

    assert_equal expected, result
  end

  test 'deferment does not work on values' do
    undef_context_methods :fragment_name_with_digest, :cache_fragment_name

    result = jbuild(<<-JBUILDER)
      json.hello(32, defer: :auto)
    JBUILDER

    expected = strip_format(<<-JS)
      (function(){
        var joints={};
        var cache={};
        var defers=[];
        return ({"data":{"hello":32},"joints":joints,"defers":defers});
      })()
    JS

    assert_equal expected, result
  end

  test 'deferment is disabled when filtering by keypath' do
    undef_context_methods :fragment_name_with_digest, :cache_fragment_name
    result = jbuild(<<-JBUILDER, breezy_filter: 'hello.world')
      json.hello defer: :auto do
        json.world 32
      end
    JBUILDER

    expected = strip_format(<<-JS)
      (function(){
        var joints={};
        var cache={};
        var defers=[];
        return ({"data":32,"action":"graft","path":"hello.world","joints":joints,"defers":defers});
      })()
    JS

    assert_equal expected, result

  end

  test 'deferment is enabled at the end of a keypath when filtering' do
    undef_context_methods :fragment_name_with_digest, :cache_fragment_name
    result = jbuild(<<-JBUILDER, breezy_filter: 'hello')
      json.hello do
        json.content defer: :auto do
          json.world 32
        end
      end
    JBUILDER

    expected = strip_format(<<-JS)
      (function(){
        var joints={};
        var cache={};
        var defers=[];
        defers.push({url:'?_breezy_filter=hello.content'});
        return ({"data":{"content":null},"action":"graft","path":"hello","joints":joints,"defers":defers});
      })()
    JS

    assert_equal expected, result
  end
end