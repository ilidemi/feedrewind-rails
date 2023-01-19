require "test_helper"

class PublishPostsServiceTest < ActiveSupport::TestCase
  test "one word" do
    slug = SubscriptionsHelper.post_slug("hello")
    assert_equal "hello", slug
  end

  test "downcase" do
    slug = SubscriptionsHelper.post_slug("Hello")
    assert_equal "hello", slug
  end

  test "two words" do
    slug = SubscriptionsHelper.post_slug("hello world")
    assert_equal "hello-world", slug
  end

  test "exclude special characters" do
    slug = SubscriptionsHelper.post_slug("hello0123456789!@#$%^&*()-=+")
    assert_equal "hello0123456789", slug
  end

  test "handle unicode" do
    slug = SubscriptionsHelper.post_slug("ด้้้้้็็็็็้้้้้็็็็็้้้้้้้้็็็็็้้้้้็็็็็้้้้้้้้็็็็็้้้้้็็็็็้้้้้้้้็็็็็้้้้้็็็็ ด้้้้้็็็็็้้้้้็็็็็้้้้้้้้็็็็็้้้้้็็็็็้้้้้้้้็็็็็้้้้้็็็็็้้้้้้้้็็็็็้้้้้็็็็ ด้้้้้็็็็็้้้้้็็็็็้้้้้้้้็็็็็้้้้้็็็็็้้้้้้้้็็็็็้้้้้็็็็็้้้้้้้้็็็็็้้้้้็็็็")
    assert_equal "", slug
  end

  test "long word" do
    slug = SubscriptionsHelper.post_slug("a" * 200)
    assert_equal "a" * 100, slug
  end

  test "limit to 10 words" do
    slug = SubscriptionsHelper.post_slug("a b c d e f g h i j k")
    assert_equal "a-b-c-d-e-f-g-h-i-j", slug
  end

  test "limit to fewer long words" do
    slug = SubscriptionsHelper.post_slug(
      "aaaaaaaaaa bbbbbbbbbb cccccccccc dddddddddd eeeeeeeeee ffffffffff gggggggggg hhhhhhhhhh iiiiiiiiii jjjjjjjjjj"
    )
    assert_equal "aaaaaaaaaa-bbbbbbbbbb-cccccccccc-dddddddddd-eeeeeeeeee-ffffffffff-gggggggggg-hhhhhhhhhh-iiiiiiiiii", slug
  end
end
