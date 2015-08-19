Spree::ProductsController.class_eval do
  before_filter :check_authorization, only: [:edit, :update, :new, :delete]
  before_filter :get_product, only: [:edit]
  before_filter :is_owner, only: [:edit, :delete]
  before_filter :load_data, only: [:new, :edit]

  def new
    @product = Spree::Product.new
    @title = "New Product"
    @body_id = 'product-manage'
  end

  def create
    uuid = Digest::SHA1.hexdigest([Time.now, rand].join)[0, 10].gsub(/\D/, '')
    params[:product][:sku] = 'S' + spree_current_user.supplier_id.to_s + '-P' + uuid
    params[:product][:supplier_id] = spree_current_user.supplier_id
    params[:product][:shipping_category_id] = 1
    params[:product][:available_on] = Time.now.to_formatted_s(:db)

    @product = Spree::Product.new product_params
    if @product.save
      variant = Spree::Variant.find_by_sku(params[:product][:sku])

      if params[:product][:taxon_ids].present?
        # params[:product][:taxon_ids] = params[:product][:taxon_ids].split(',')
        taxonomy = Spree::Taxonomy.find_by_id(params[:product][:taxon_ids])
        taxon = Spree::Taxon.where("parent_id is NULL and taxonomy_id = ?", taxonomy.id)
        if !taxon.nil? and !@product.taxons.include?(taxon)
          @product.taxons << taxon
        end
      end

      if params[:images].present?
        params[:images].each do |key, image|
          logger.debug key.inspect
          logger.debug image.inspect
          params[:image] = {}
          params[:image][:attachment] = image
          # params[:image][:alt] = 'Some Alt text'
          params[:image][:position] = key.to_i + 1
          params[:image][:viewable_type] = 'Spree::Variant'
          params[:image][:viewable_id] = variant.id
          logger.debug params[:image].inspect
          attachment = Spree::Image.new image_params;
          attachment.save
          logger.debug attachment.inspect
        end
      end


      # if params[:product][:option_type_ids].present?
      #   option_types = []
      #   params[:product][:option_type_ids].each do |id|
      #     option = Spree::OptionType.find_by_id(id)
      #     if option.present?
      #       option_types << option
      #     end
      #   end
      #   @product.option_types = option_types
      # end
      #
      # if params[:variants].present?
      #   # TODO improving variant creation
      #   # params[:variants].each do |key, values|
      #   #   variant = Spree::Variant.new(values)
      #   #   abort variant.inspect
      #   #   variant[:sku] = params[:product][:sku] + 'v-' + key
      #   #   @product.variants = variant
      #   # end
      #   @product.build_variants_from_option_values_hash(params[:variants])
      # end

      redirect_to @product
    else
      render 'new'
    end

  end

  def edit
    @body_id = 'product-manage'
  end

  def update
    if @product.update_attributes supplier_params
      redirect_to @product
    else
      render 'edit'
    end
  end

  private

  def check_authorization
    action = params[:action].to_sym
    resource = Spree::Product

    authorize! action, resource, session[:access_token]
  end

  def is_owner
    unless spree_current_user.supplier_id === @product.supplier_id
      flash[:error] = "You don't hav permission to access this content!"
      redirect_to @product
    end
  end

  def get_product
    @product = Spree::Product.friendly.find(params[:id])
  end

  def product_params
    permit = permitted_product_attributes + [:supplier_id]
    params.require(:product).permit(permit)
  end

  def image_params
    params.require(:image).permit(Spree::PermittedAttributes.image_attributes)
  end

  def variant_params
    params.require(:variant).permit(Spree::PermittedAttributes.variant_attributes)
  end

  def load_data
    @option_types = Spree::OptionType.order(:name)
    values = Spree::OptionValue.all
    @option_values =  values.to_json(:only => [:id, :name, :presentation, :option_type_id])
    @taxonomy = Spree::Taxon.order(:name).where(:depth => 0)
    @sub1 = Spree::Taxon.order(:name).where(:depth => 1)
    @sub2 = Spree::Taxon.order(:name).where(:depth => 2)

    # @tax_categories = TaxCategory.order(:name)
    # @shipping_categories = ShippingCategory.order(:name)
  end
end