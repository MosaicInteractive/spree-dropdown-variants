# Uncomment this if you reference any of your controllers in activate
# require_dependency 'application'

class DropdownVariantsExtension < Spree::Extension
  version "0.1.0"
  description "Dropdown Variants displays variants on the product base in HTML select tags
               instead of the default radio buttons."
  url "http://github.com/timcase/Spree-Dropdown-Variants"

  def activate
    ProductsHelper.module_eval do
      def instock_option_values(product, option_type)
        instock = product.variants.find_all{|variant| variant.in_stock? || Spree::Config[:show_zero_stock_products]}
        uniq_option_values = instock.collect(&:option_values).flatten.uniq
        uniq_option_values.find_all{|ov| ov.option_type == option_type}
      end
      
      def show_variant_images?
        @product.has_variants? && @selected_variant && !@selected_variant.images.empty?
      end
    end

    Variant.class_eval do
      def self.find_by_option_types_and_product(option_types, product)
        join_clause = ''
        and_clause = ''

        option_types.each_with_index do |option_type, i|
          join_clause << " INNER JOIN option_values_variants ovv#{i}
                           ON v.id = ovv#{i}.variant_id "
          and_clause << " AND ovv#{i}.option_value_id = #{option_type.last} "
        end
        Variant.find_by_sql("SELECT v.* FROM variants v
                             #{join_clause}
                             WHERE v.product_id = #{product} 
                             #{and_clause};").first
      end
    end
    
    OrdersController.class_eval do
      create.before << :add_variants_from_drop_downs

      def add_variants_from_drop_downs
        if params[:option_types] and params[:product]
          variant = Variant.find_by_option_types_and_product(params[:option_types], params[:product])
          quantity = params[:quantity].to_i
          @object.add_variant(variant, quantity) if quantity > 0
        end
      end      
    end
    
    Order.class_eval do
      alias_method :add_variant_original, :add_variant
      alias_method :validate_original, :validate
      
      def validate
        self.errors.add_to_base(@variant_errors) unless @variant_errors.nil?
      end
      
      def add_variant(variant, quantity = 1)
        if variant.nil? || (!variant.in_stock? && !Spree::Config[:allow_backorders])
          @variant_errors = I18n.t('variant_out_of_stock') 
        else
          self.add_variant_original(variant, quantity)
        end
      end
    end
    
    ProductsController.class_eval do
      append_before_filter :override_selected, :only => :show
      
      def selected_variant
        @product ||= Product.available.find(params[:id])
        @variants = @product.variants
        unless @selected_variant = Variant.find_by_option_types_and_product(params[:option_types], params[:product])
          @error_message = I18n.t('variant_does_not_exist')
          @selected_variant = Variant.find(params[:variant])
        end
      end
      
      private
      
      def override_selected
        @selected_variant = @product.default_variant
      end
    end
    
    Product.class_eval do
      def default_variant
        options = {}
        self.option_types.each do |option_type|
          options[option_type.id.to_s] = instock_option_values(option_type).reverse.first.id.to_s
        end
        @default_variant ||= Variant.find_by_option_types_and_product(options, self.id) || self.master
      end
      
      private
      
      def instock_option_values(option_type)
        instock = self.variants.find_all{|variant| variant.in_stock? || Spree::Config[:show_zero_stock_products]}
        uniq_option_values = instock.collect(&:option_values).flatten.uniq
        uniq_option_values.find_all{|ov| ov.option_type == option_type}
      end
    end
  end
  
end
