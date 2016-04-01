class Spree::SuppliersController < Spree::StoreController
  before_filter :check_authorization, only: [:edit, :update, :new, :verify, :destroy]
  before_filter :is_new_supplier, only: [:new]
  before_filter :supplier, only: [:edit, :update, :show, :verify, :destroy]
  before_filter :is_supplier, only: [:edit, :update, :verify, :destroy]

  def index
    suppliers = Spree::Supplier.joins("LEFT JOIN spree_favorites ON spree_favorites.favorable_type = 'Spree::Supplier' AND spree_favorites.favorable_id = spree_suppliers.id")
                .group('spree_suppliers.id')
                .order('COUNT(spree_favorites.favorable_id) DESC')
    if try_spree_current_user && spree_current_user.has_spree_role?("admin")
      @suppliers = suppliers.page(params[:page]).per(15)
    else
      @suppliers = suppliers.where(:active => true).page(params[:page]).per(15)
    end
    @title = "Pet Shops"
    @body_id = 'shops'
  end

  def new
    @supplier = Spree::Supplier.new
    @title = "New Shop"
    @body_id = 'shop-manage'
    @selected = 'new'
  end

  def create
    params[:supplier][:email] = spree_current_user.email
    @supplier = Spree::Supplier.new supplier_params
    if @supplier.save
      flash[:success] = "Your shop has been created! Verify your account."
      redirect_to verify_supplier_path(@supplier)
    else
      render "new"
    end
  end

  def show
    @products = @supplier.products
    unless (try_spree_current_user && spree_current_user.supplier_id == @supplier.id ) || (try_spree_current_user && spree_current_user.has_spree_role?("admin"))
      @products = @products.available
    end
    @body_id = 'shop-details'
  end

  def edit
    @body_id = 'shop-manage'
  end

  def update
    if params[:remove_banner].present?
      @supplier.remove_banner = params[:remove_banner]
    end
    if @supplier.update_attributes(supplier_params)
      if(!params[:supplier][:banner].present? and params[:supplier][:crop].present?)
        @supplier.reprocess_banner
      end
      flash[:success] = "Your shop has been updated!"
      redirect_to @supplier
    else
      logger.debug @supplier.errors.messages.inspect
      render "edit"
    end
  end

  def destroy
    if @supplier.delete
      @supplier.products.delete_all
      flash[:success] = "Your shop has been deleted!"
      redirect_to "/shop"
    end
  end

  private

  def check_authorization
    if try_spree_current_user.nil?
      redirect_to '/user' and return
    end

    action = params[:action].to_sym
    resource = Spree::Supplier
    authorize! action, resource, session[:access_token]
  end

  def is_new_supplier
    unless !spree_current_user.supplier?
      redirect_to new_design_path
    end
  end

  def supplier
    @supplier = Spree::Supplier.friendly.find(params[:id])
    unless @supplier.public? || (try_spree_current_user && (spree_current_user.supplier_id === @supplier.id || spree_current_user.has_spree_role?("admin")))
      flash[:warning] = "Pet shop not available!"
      redirect_to suppliers_path
    end
  end

  def is_supplier
    unless try_spree_current_user && (spree_current_user.supplier_id === @supplier.id)
      flash[:error] = "You don't hav permission to access this content!"
      redirect_to @supplier and return
    end
  end

  def supplier_params
    # TODO - crop field currently applies to the banner - may need to rename or change
    params.require(:supplier).permit(:name, :slug, :description, :banner, :email, :crop,
    :hero, :profile_image, :facebook_url, :twitter_url, :instagram_url, :pinterest_url)
  end
end