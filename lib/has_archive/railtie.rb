module HasArchive
  class Railtie < Rails::Railtie
    initializer 'has_archive.initialize' do
      ActiveSupport.on_load(:active_record) do

        # Handle custom contraint options (hack needed for has_archive)
        ActiveRecord::Associations::AssociationScope.class_exec do
          alias_method :add_constraints!, :add_constraints

          def add_constraints(scope)
            if options[:custom_constraints]
              scope.instance_exec(association.owner, &options[:custom_constraints])
            else
              add_constraints!(scope)
            end
          end
        end

        # Allow passing the options `custom_constraints` to relationships
        ActiveRecord::Associations::Builder::Association.valid_options << :custom_constraints

        # Handle the constraint of the `type` column required for histories
        ActiveRecord::Inheritance::ClassMethods.class_exec do
          alias_method :type_condition!, :type_condition

          def type_condition(table = arel_table)
            sti_column = table[inheritance_column.to_sym]
            sti_names  = ([self] + ancestors.select { |x| x < ActiveRecord::Base }).map { |model| model.sti_name }

            sti_column.in(sti_names.uniq)
          end
        end

        # Include the gem for archival purposes
        ActiveRecord::Base.__send__(:include, HasArchive)
      end
    end
  end
end
