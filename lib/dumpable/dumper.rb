module Dumpable
  class Dumper
    attr_accessor :dumpee, :options, :id_padding, :dumps
    attr_accessor :done

    def initialize(dumpee, options={})
      @done = []
      @dumpee = dumpee
      @options = Dumpable.config.merge(options || {})
      @id_padding = @options[:id_padding] || (@dumpee.class.respond_to?(:dumpable_options) && @dumpee.class.dumpable_options[:id_padding]) || Dumpable.config.id_padding
      @dumps = @options[:dumps] || (@dumpee.class.respond_to?(:dumpable_options) && @dumpee.class.dumpable_options[:dumps])
      @lines = []
    end

    def dump
#      puts "DUMP: %#{@dumps.inspect}"
      recursive_dump(@dumpee, @dumps)
      @lines = [generate_insert_query(@dumpee)]
      Dumpable::FileWriter.write(@lines.flatten.compact.reverse, options)
    end

    def self.dump(*records_and_collections)
      options = records_and_collections.extract_options!
#      lines = []
      records_and_collections.each do |record_or_collection|
        if record_or_collection.is_a?(Array) || record_or_collection.is_a?(ActiveRecord::Relation) || (record_or_collection.is_a?(Class) && record_or_collection.ancestors.include?(ActiveRecord::Base))
          record_or_collection = record_or_collection.all if record_or_collection.is_a?(Class) && record_or_collection.ancestors.include?(ActiveRecord::Base)
          record_or_collection.each do |object|
            lines = new(object, options).dump
#            Dumpable::FileWriter.write(lines.flatten.compact.reverse, options)
          end
        else
          lines = new(record_or_collection, options).dump
#      Dumpable::FileWriter.write(lines.flatten.compact.reverse, options)
        end
      end
      #Dumpable::FileWriter.write(lines.flatten.compact.reverse, options)
    end

    private
    def recursive_dump(object, dumps)
      if dumps.nil?

      elsif dumps.is_a?(Array)
        dumps.each do |mini_dump|
           recursive_dump(object, mini_dump)
        end
      elsif dumps.is_a?(Hash)
        dumps.each do |key, value|
          recursive_dump(object, key)
          Array(object.send(key)).each { |child| recursive_dump(child, value) }
        end
      elsif dumps.is_a?(Symbol) || dumps.is_a?(String)
				# iterate through

        Array(object.send(dumps)).each do |child_object|

          reflection = object.class.reflect_on_association(dumps.to_sym)
#          opposite_reflection = child_object.class.reflect_on_association(object.class.name.downcase.to_sym)

#        take note that this current version of dumpable doesn't handle padding since we're going to disable padding below

#        if reflection.macro == :belongs_to
#          puts "\n\n\n\n\nhere #{reflection.macro} - #{object.inspect} - #{reflection.inspect}"
#          object.send("#{reflection.foreign_key}=", object.id + @id_padding)
#        # has_many should update both sides
#        elsif [:has_many, :has_one].include? reflection.macro
#          if reflection.respond_to?(:foreign_key)
#            object.send("#{reflection.foreign_key}=", object.id + @id_padding)
#          else
#            object.send("#{reflection.primary_key_name}=", object.id + @id_padding)
#          end
#        end
          @lines = [generate_insert_query(child_object)]
          Dumpable::FileWriter.write(@lines.flatten.compact.reverse, options)
        end
      end
    end

    # http://invisipunk.blogspot.com/2008/04/activerecord-raw-insertupdate.html
    def generate_insert_query(object)
      skip_columns = Array(@options[:skip_columns] || (object.class.respond_to?(:dumpable_options) && object.class.dumpable_options[:skip_columns])).map(&:to_s)
      cloned_attributes = object.attributes.clone
      return nil unless cloned_attributes["id"].present?
      cloned_attributes["id"] += @id_padding

      key_values = cloned_attributes.collect do |key,value|
        # check for enum
        if object.defined_enums.has_key?(key)
          value = object.class.send(key.pluralize)[value]
        end
        next if !object.class.column_names.include?(key)
        [key, dump_value_string_from_helper(object, key, value)] unless skip_columns.include?(key.to_s)
      end.compact
      keys = key_values.collect{ |item| "#{item[0]}" }.join(", ")
      values = key_values.collect{ |item| item[1].to_s }.join(", ")

      "INSERT INTO #{object.class.table_name} (#{ keys }) VALUES (#{ values }) ON CONFLICT DO NOTHING;"
    end

    def dump_value_string_from_helper(dumpable_object,key, value)
          begin
            value = ActiveRecord::Relation::QueryAttribute.new(
              key,
              dumpable_object.attributes_before_type_cast[key],
              dumpable_object.class.type_for_attribute(key)
            )

            ActiveRecord::Base.connection.quote(value.value_for_database)
          rescue ActiveRecord::SerializationTypeMismatch => e
            return ActiveRecord::Base.connection.quote(dumpable_object.attributes_before_type_cast[key])
          end
    end

    # http://invisipunk.blogspot.com/2008/04/activerecord-raw-insertupdate.html
    def dump_value_string(value)
      case value.class.to_s
        when "Time", "ActiveSupport::TimeWithZone"
          "\'#{value.strftime("%Y-%m-%d %H:%M:%S")}\'"
        when "NilClass"
          "NULL"
        when "Fixnum" || "Integer"
          value
        when "String"
          "E\'#{value.gsub(/'/, "\\\\'")}\'"
        when "FalseClass"
          "\'0\'"
        when "TrueClass"
          "\'1\'"
        when "ActiveSupport::HashWithIndifferentAccess"
          "\'#{value.to_yaml.gsub(/'/, "\\\\'")}\'"
        when "Array"
          "E\'#{value}\'"
        when "Hash"
          "\'#{value.to_json}\'"
        else
          "\'#{value}\'"
      end
    end
  end
end
