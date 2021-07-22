module Dumpable
  module ActiveRecordExtensions
    extend ActiveSupport::Concern

    def dump(options={})
      Dumpable::Dumper.dump(self, options)
    end

    module ClassMethods
        cattr_accessor :root, :seen_before, :blacklist

        def get_class_from_name(class_name)
          begin
            return class_name.constantize
          rescue NameError => e
            puts "Nameerror hit, cannot find Class: #{e.inspect}"
            self.const_get(class_name.to_sym)
          rescue Exception => e
            raise "Exception getting class_from_name: #{e.inspect}"
          end
        end

        def all_associations
          root = []
          class_names = self.reflect_on_all_associations.map(&:name) - [:versions]
          self.reflect_on_all_associations.each do |m|
            begin
              hh = {}
              hh[m.name] = self.get_class_from_name(m.class_name).dump_associations.compact - [:versions]
              root << hh
            rescue Exception => e
              puts e.inspect
            end

          end
          return root
        end

        def dump_associations
          self.reflect_on_all_associations.map do |m|
            begin
              if m.name == :versions
                next
              end

              m.name
            rescue Exception => e
              puts "#{e.inspect}"
              next
            end
          end
        end

        def dumpable(options={})
        class_eval do
          cattr_accessor :dumpable_options
        end
        self.dumpable_options = options
      end

      def dump(options={})
        Dumpable::Dumper.dump(self, options)
      end
    end
  end
end
