class Spree::Admin::SuppliersController < Spree::Admin::ResourceController
  after_filter :delete_products, only: [:destroy]

  def edit
    respond_with(@object) do |format|
      format.html { render :layout => !request.xhr? }
      format.js   { render :layout => false }
    end
  end

  def new
    @object = Spree::Supplier.new()
  end

  private

    def collection
      params[:q] ||= {}
      params[:q][:meta_sort] ||= "name.asc"
      @search = Spree::Supplier.search(params[:q])
      @collection = @search.result.page(params[:page]).per(Spree::Config[:orders_per_page])
    end

    def find_resource
      Spree::Supplier.friendly.find(params[:id])
    end

    def location_after_save
      spree.edit_admin_supplier_path(@object)
    end

    def delete_products
      @object.products.destroy_all
    end

end
