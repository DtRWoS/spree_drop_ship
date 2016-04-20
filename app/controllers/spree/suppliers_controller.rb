class Spree::SuppliersController < Spree::StoreController
  before_filter :check_authorization, only: [:edit, :update, :new, :verify, :destroy]
  before_filter :is_new_supplier, only: [:new]
  before_filter :supplier, only: [:edit, :update, :show, :verify, :destroy]
  before_filter :is_supplier, only: [:edit, :update, :verify, :destroy]
  before_filter :social_counts, only: [:show]

  def index
    suppliers = Spree::Supplier.joins("LEFT JOIN spree_favorites ON spree_favorites.favorable_type = 'Spree::Supplier' AND spree_favorites.favorable_id = spree_suppliers.id")
                .where(:verified_brand => false)
                .group('spree_suppliers.id')
                .order('COUNT(spree_favorites.favorable_id) DESC')
    if try_spree_current_user && spree_current_user.has_spree_role?("admin")
      @suppliers = suppliers.page(params[:page]).per(15)
    else
      @suppliers = suppliers.where(:active => true).page(params[:page]).per(15)
    end
    @title = "Shops"
    @body_id = "shops"
  end

  def brands
    suppliers = Spree::Supplier.joins("LEFT JOIN spree_favorites ON spree_favorites.favorable_type = 'Spree::Supplier' AND spree_favorites.favorable_id = spree_suppliers.id")
                .where(:verified_brand => true)
                .group('spree_suppliers.id')
                .order('COUNT(spree_favorites.favorable_id) DESC')
    if try_spree_current_user && spree_current_user.has_spree_role?("admin")
      @suppliers = suppliers.page(params[:page]).per(15)
    else
      @suppliers = suppliers.where(:active => true).page(params[:page]).per(15)
    end
    @title = "Brands"
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
      flash[:success] = "Your shop has been created! Create a new design."
      redirect_to new_design_path(:onboard => true)
    else
      render "new"
    end
  end

  def show
    products = @supplier.products
    unless (try_spree_current_user && spree_current_user.supplier_id == @supplier.id ) || (try_spree_current_user && spree_current_user.has_spree_role?("admin"))
      products = products.available
    end
    @products = products.sort_by { |p| [p.favorites.count, p.featured ? 1 : 0, p.created_at]}.reverse
    @body_id = 'shop-details'
  end

  def edit
    @body_id = 'shop-manage'
  end

  def update
    delete_images_check
    if @supplier.update_attributes(supplier_params)
      reprocess_images_check
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
  def reprocess_images_check
    @supplier.reprocess_banner if @supplier.cropping?('banner_crop')
    @supplier.reprocess_profile_image if @supplier.cropping?('profile_image_crop')
    @supplier.reprocess_hero if @supplier.cropping?('hero_crop')
  end

  def delete_images_check
    if params[:remove_banner].present?
      @supplier.remove_banner = params[:remove_banner]
    end
    if params[:remove_profile_image].present?
      @supplier.remove_profile_image = params[:remove_profile_image]
    end
    if params[:remove_hero].present?
      @supplier.remove_hero = params[:remove_hero]
    end
  end

  def check_authorization
    if try_spree_current_user.nil?
      redirect_to '/user' and return
    end

    action = params[:action].to_sym
    resource = Spree::Supplier
    authorize! action, resource, session[:access_token]
  end

  def is_new_supplier
    if spree_current_user.supplier?
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
    params.require(:supplier).permit(:name, :slug, :description, :banner, :email, :hero, :profile_image, :url, :url_name,
    :facebook_url, :twitter_url, :instagram_url, :pinterest_url, :banner_crop, :profile_image_crop, :hero_crop)
  end

  def social_counts
    if @supplier.verified_brand?
      @fb_fans = facebook_count()
      @ig_followers = instagram_count()
      @tw_followers = twitter_follower_count()
      @pi_followers = pinterest_count()
    end
  end

  def twitter_access_token
    ### use this to regain twitter access token if lost/invalidated ###
    require 'httpclient'
    require 'base64'
    require 'uri'

    credentials = "#{ENV['TW_CONSUMER_KEY']}:#{ENV['TW_CONSUMER_SECRET']}"
    encoded = Base64.encode64(credentials).split(/\n/).join('')
    headers = {
        'Authorization' => "Basic #{encoded}",
        'Content-Type' => 'application/x-www-form-urlencoded;charset=UTF-8'
    }
    uri = URI.parse('https://api.twitter.com/oauth2/token')
    http_client = HTTPClient.new
    response = http_client.post(uri, {grant_type: 'client_credentials'}, headers)
    JSON.parse(response.body)['access_token']
  end

  def twitter_follower_count()
    require 'httpclient'
    require 'uri'

    if(!@supplier.twitter_url.blank?)
      twitter_url = @supplier.twitter_url
      username = twitter_url.match('/(?:(?:http|https):\/\/)?(?:www.)?(?:twitter.com)\/([A-Za-z0-9-_]+)/*')
      if(!username.nil?)
        username = username[1]
        headers = {
            'Authorization' => "Bearer #{ENV['TW_ACCESS_TOKEN']}"
        }
        follower_url = 'https://api.twitter.com/1.1/users/show.json?screen_name=' + username
        uri = URI.parse(follower_url)
        http_client = HTTPClient.new
        response = http_client.get(uri, nil, headers)
        JSON.parse(response.body)['followers_count']
      end
    end
  end

  def pinterest_count()
    require 'open-uri'
    require 'open_uri_redirections'

    if(!@supplier.pinterest_url.blank?)
      pinterest_url = @supplier.pinterest_url
      url_check = pinterest_url.match('/(?:(?:http|https):\/\/)?(?:www.)?(?:pinterest.com)\/([A-Za-z0-9-_]+)/*')
      if(!url_check.nil?)
        doc = Nokogiri::HTML(open(pinterest_url, {ssl_verify_mode: OpenSSL::SSL::VERIFY_NONE, :allow_redirections => :safe}))
        doc.xpath("//meta[@name='pinterestapp:followers']").first.attributes['content'].value
      end
    end
  end

  def facebook_count()
    require 'httpclient'
    require 'uri'

    if(!@supplier.facebook_url.blank?)
      facebook_url = @supplier.facebook_url
      page_name = facebook_url.match('/(?:(?:http|https):\/\/)?(?:www.)?(?:facebook.com)\/([A-Za-z0-9-_]+)/*')
      if(!page_name.nil?)
        page_name = page_name[1]
        headers = {
            'Authorization' => "Bearer #{ENV['FB_ACCESS_TOKEN']}"
        }
        url = 'https://graph.facebook.com/' + page_name + '?fields=likes'
        uri = URI.parse(url)
        http_client = HTTPClient.new
        response = http_client.get(uri, nil, headers)
        JSON.parse(response.body)['likes']
      end
    end
  end

  def instagram_count()
    require 'httpclient'
    require 'uri'

    if(!@supplier.instagram_url.blank?)
      instagram_url = @supplier.instagram_url
      username = instagram_url.match('/(?:(?:http|https):\/\/)?(?:www.)?(?:instagram.com|instagr.am)\/([A-Za-z0-9-_]+)/*')
      if(!username.nil?)
        search_for_id_url = 'https://api.instagram.com/v1/users/search?q=' + username[1] + '&access_token=' + ENV['IG_ACCESS_TOKEN']

        #first call to grab the user id
        uri = URI.parse(search_for_id_url)
        http_client = HTTPClient.new
        response = http_client.get(uri)
        instagram_id = JSON.parse(response.body)['data'][0]['id']

        #second call to get the follower count
        follower_uri = URI.parse("https://api.instagram.com/v1/users/#{instagram_id}/?access_token=#{ENV['IG_ACCESS_TOKEN']}")
        follower_http_client = HTTPClient.new
        follower_response = follower_http_client.get(follower_uri)
        JSON.parse(follower_response.body)['data']['counts']['followed_by']
      end
    end
  end
end