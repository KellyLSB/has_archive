require 'active_support/core_ext/module/attribute_accessors'
require 'active_support/inflector'
require 'active_support/concern'

require 'has_archive/version'
require 'has_archive/archive_extension'

module HasArchive
  require 'has_archive/railtie' if defined?(Rails)
  extend ActiveSupport::Concern

  # Store all the archive klasses
  mattr_accessor :archive_klasses,
    instance_accessor: false

  mattr_accessor :archives,
    instance_accessor: false

  module ClassMethods
    def has_archive(name = :archive, args = {})
      default_scope { archive! }

      # Allow name to be a hash
      if name.is_a?(Hash) && args.empty?
        args, name = name, name[:name] || :archive
      end

      # Prepare the cache for has_archive
      HasArchive.archive_klasses ||= []
      HasArchive.archives ||= {}

      # Don't using has_archive on archive klasses (because they inherit)
      if HasArchive.archive_klasses.include?("#{self}".underscore.to_sym)
        return false
      end

      # Add name of the klass to the cache
      klass = "#{self}".underscore.to_sym
      HasArchive.archives[klass] ||= []
      HasArchive.archives[klass] << name

      # Class level data stores explaining where and how to get
      # the information required to archive, etc...
      cattr_accessor "#{name}_object", instance_writer: false
      cattr_accessor "#{name}_column", instance_writer: false

      # Is this a archived record
      define_method("is_#{name}?") do
        instance_of?(archive_object)
      end

      # Aliasing of the attribute accessors
      alias_method :is_archive?, "is_#{name}?"
      alias_method :has_archive_object, "#{name}_object"
      alias_method :has_archive_column, "#{name}_column"

      define_singleton_method(:has_archive_object) do
        __send__("#{name}_object")
      end

      define_singleton_method(:has_archive_column) do
        __send__("#{name}_column")
      end

      # Get the archive class name
      if args[:class_name] && ("#{args[:class_name]}".camelize.constantize rescue false)
        archive_class = "#{args[:class_name]}".camelize
      else
        archive_class = "::#{self}::" + "#{name}".camelize

        class_eval <<-CODE
          class #{archive_class} < #{self}
            after_initialize :readonly!, unless: :new_record?
          end
        CODE
      end

      # Constantiate the archive class
      archive_object = archive_class.constantize

      # Ensure the archive class directly inherits self
      unless archive_object.superclass == self
        raise NameError,
          "has_archive: `class_name` must be a child object of the model with an archive."
      end

      # Add the archive class to the cache to keep additionals from being created
      HasArchive.archive_klasses << archive_class.underscore.to_sym

      # Set the values of the archive object
      __send__("#{name}_object=", archive_object)
      __send__("#{name}_column=", "#{name}_of")

      has_many name,
        extend: HasArchive::ArchiveExtension,
        custom_constraints: ->(owner) {
          column = owner.__send__("#{name}_column")
          id = owner.__send__(column) || owner.id

          columns = ['id', column].map do |col|
            "#{owner.class.table_name}.#{col}"
          end

          @archive_access = column
          where("? IN (#{columns.join(', ')})", id)
        },
        dependent: :delete_all

      # Callbacks
      after_initialize do
        self.type = "#{self.class}" unless type
      end

      # After initialize grab the attributes for future archival
      after_initialize unless: [:new_record?, :is_archive?] do
        @__has_archive_cache   = self.attributes
        @__has_archive_changed = false
      end

      # Before we validate, determine if something has changed. It will save us some time.
      before_validation on: :update, unless: :is_archive? do
        @__has_archive_changed = changed?
      end

      # Handle duplication of objects
      after_save on: :update, unless: :is_archive? do
        return false unless @__has_archive_changed

        # Delete items to regenerate
        keys = [:id]
        [keys, keys.map(&:to_s)].flatten.each do |k|
          @__has_archive_cache.delete(k)
        end

        # Create the new model with history column data
        # marking it as part of history for scoping queries
        has_archive_object.create(@__has_archive_cache.merge(
          __send__("#{name}_column") => id,
          type: "#{__send__("#{name}_object")}"
        ))

        # Reset attributes
        @__has_archive_cache   = self.attributes
        @__has_archive_changed = false
        true
      end

      # Handle reloading the data after we create an object
      after_commit on: :create, unless: :is_archive? do
        reload # Reload all the data

        # Reset attributes
        @__has_archive_cache   = self.attributes
        @__has_archive_changed = false
      end

      # Return the archive class
      archive_object
    end
  end
end
