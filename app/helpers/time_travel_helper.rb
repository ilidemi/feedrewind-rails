require "active_support/core_ext/module/redefine_method"

module TimeTravelHelper
  def self.travel_to(timestamp)
    self.stub_object(Time, :now) { at(timestamp.to_i) }
    self.stub_object(Date, :today) { jd(timestamp.to_date.jd) }
    self.stub_object(DateTime, :now) { jd(timestamp.to_date.jd, timestamp.hour, timestamp.min, timestamp.sec, Rational(timestamp.utc_offset, 86400)) }
    nil
  end

  def self.travel_back
    self.unstub_object(Time, :now)
    self.unstub_object(Date, :today)
    self.unstub_object(DateTime, :now)
    nil
  end

  private

  def self.stub_object(object, method_name, &block)
    backup_name = self.backup_name(method_name)
    unless object.methods.include?(backup_name.to_sym)
      object.singleton_class.alias_method(backup_name, method_name)
    end

    object.define_singleton_method(method_name, &block)
  end

  def self.unstub_object(object, method_name)
    backup_name = self.backup_name(method_name)
    singleton_class = object.singleton_class
    return unless singleton_class.method_defined?(backup_name)

    singleton_class.silence_redefinition_of_method(method_name)
    singleton_class.alias_method(method_name, backup_name)
    singleton_class.undef_method(backup_name)
  end

  def self.backup_name(method_name)
    "__feedrewind_stub__#{method_name}"
  end
end