class Spree::Supplier < Spree::Base
  SLUG_FORMAT = /([[:lower:]]|[0-9]+-?[[:lower:]])(-[[:lower:]0-9]+|[[:lower:]0-9])*/

  extend FriendlyId
  friendly_id :name, use: :slugged

  acts_as_paranoid

  attr_accessor :password, :password_confirmation, :remove_banner, :remove_profile_image, :remove_hero

  has_attached_file :banner, :styles => { :large => ["655x230#",:jpg], :small => ["320x112#",:jpg] },
                    :default_style => :large,
                    :default_url => "noimage/:attachment-:style.png",
                    :processors => [:cropper],
                    :convert_options => {
                        :all => "-strip -auto-orient -quality 75 -interlace Plane -colorspace sRGB"
                    },
                    :s3_credentials => {
                        :access_key_id => ENV["AWS_ACCESS_KEY_ID"],
                        :secret_access_key => ENV["AWS_SECRET_ACCESS_KEY"]
                    },
                    :storage => :s3,
                    :s3_headers => {"Cache-Control" => "max-age=31557600"},
                    :s3_protocol => "https",
                    :bucket => ENV["S3_BUCKET_NAME"],
                    :url => ":s3_domain_url",
                    :path => "/suppliers/:id/:attachment/:style.:extension"

  has_attached_file :hero, :styles => { :large => ["1360x418#", :jpg], :small => ["320x98#"] },
                    :default_style => :large,
                    :default_url => "noimage/:attachment-:style.png",
                    :processors => [:cropper],
                    :convert_options => {
                        :all => "-strip -auto-orient -quality 75 -interlace Plane -colorspace sRGB"
                    },
                    :s3_credentials => {
                        :access_key_id => ENV["AWS_ACCESS_KEY_ID"],
                        :secret_access_key => ENV["AWS_SECRET_ACCESS_KEY"]
                    },
                    :storage => :s3,
                    :s3_headers => {"Cache-Control" => "max-age=31557600"},
                    :s3_protocol => "https",
                    :bucket => ENV["S3_BUCKET_NAME"],
                    :url => ":s3_domain_url",
                    :path => "/suppliers/:id/:attachment/:style.:extension"

  has_attached_file :profile_image, :styles => { :large => ["500x500#", :jpg], :medium => ["300x300#", :jpg], :small => ["150x150#"] },
                    :default_style => :medium,
                    :default_url => "noimage/:attachment-:style.png",
                    :processors => [:cropper],
                    :convert_options => {
                        :all => "-strip -auto-orient -quality 75 -interlace Plane -colorspace sRGB"
                    },
                    :s3_credentials => {
                        :access_key_id => ENV["AWS_ACCESS_KEY_ID"],
                        :secret_access_key => ENV["AWS_SECRET_ACCESS_KEY"]
                    },
                    :storage => :s3,
                    :s3_headers => {"Cache-Control" => "max-age=31557600"},
                    :s3_protocol => "https",
                    :bucket => ENV["S3_BUCKET_NAME"],
                    :url => ":s3_domain_url",
                    :path => "/suppliers/:id/:attachment/:style.:extension"

  validates_attachment_content_type :banner, :content_type => /\Aimage/
  validates_attachment_content_type :hero, :content_type =>/\Aimage/
  validates_attachment_content_type :profile_image, :content_type =>/\Aimage/

  #==========================================
  # Associations

  belongs_to :address, class_name: 'Spree::Address'
  accepts_nested_attributes_for :address

  if defined?(Ckeditor::Asset)
    has_many :ckeditor_pictures
    has_many :ckeditor_attachment_files
  end
  has_many   :products, through: :variants
  has_many   :shipments, through: :stock_locations
  has_many   :stock_locations
  has_many   :supplier_variants
  has_many   :users, class_name: Spree.user_class.to_s
  has_many   :variants, through: :supplier_variants

  #==========================================
  # Validations

  validates :commission_flat_rate,   presence: true
  validates :commission_percentage,  presence: true
  validates :email,                  presence: true, email: true, uniqueness: true
  validates :name,                   presence: true, uniqueness: true
  validates :url,                    format: { with: URI::regexp(%w(http https)), allow_blank: true }
  validates :slug,                   presence: true, uniqueness: true,
      format: {with: Regexp.new('\A' + SLUG_FORMAT.source + '\z')}

  #==========================================
  # Callbacks

  after_create :assign_user
  # after_create :create_stock_location
  after_create :send_welcome, if: -> { SpreeDropShip::Config[:send_supplier_email] }
  after_create :save_banner, if: -> {self.cropping?('banner_crop')}
  after_create :save_profile_image, if: -> {self.cropping?('profile_image_crop')}
  after_create :save_hero, if: -> {self.cropping?('hero_crop')}
  before_create :set_commission
  before_validation :check_url
  before_save :delete_banner, if: -> {self.remove_banner == 'true'}
  before_save :delete_profile_image, if: -> {self.remove_profile_image == 'true'}
  before_save :delete_hero, if: -> {self.remove_hero == 'true'}

  #==========================================
  # Instance Methods
  scope :active, -> { where(active: true) }

  def cropping?(crop_field)
    !self[crop_field].blank?
  end

  def save_banner
    banner.assign(banner)
    banner.save
  end

  def save_profile_image
    profile_image.assign(profile_image)
    profile_image.save
  end

  def save_hero
    hero.assign(hero)
    hero.save
  end

  def reprocess_banner
    banner.reprocess!
  end

  def reprocess_profile_image
    profile_image.reprocess!
  end

  def reprocess_hero
    hero.reprocess!
  end

  def deleted?
    deleted_at.present?
  end

  def user_ids_string
    user_ids.join(',')
  end

  def user_ids_string=(s)
    self.user_ids = s.to_s.split(',').map(&:strip)
  end

  # Retreive the stock locations that has available
  # stock items of the given variant
  def stock_locations_with_available_stock_items(variant)
    stock_locations.select { |sl| sl.available?(variant) }
  end

  #==========================================
  # Protected Methods

  protected

    def assign_user
      if self.users.empty?
        if user = Spree.user_class.find_by_email(self.email)
          self.users << user
          self.save
        end
      end
    end

    def check_url
      unless self.url.blank? or self.url =~ URI::regexp(%w(http https))
        self.url = "http://#{self.url}"
      end
    end

    def create_stock_location
      if self.stock_locations.empty?
        location = self.stock_locations.build(
          active: true,
          country_id: self.address.try(:country_id),
          name: self.name,
          state_id: self.address.try(:state_id)
        )
        # It's important location is always created.  Some apps add validations that shouldn't break this.
        location.save validate: false
      end
    end

    def send_welcome
      begin
        Spree::SupplierMailer.welcome(self.id).deliver_later!
        # Specs raise error for not being able to set default_url_options[:host]
      rescue => ex #Errno::ECONNREFUSED => ex
        Rails.logger.error ex.message
        Rails.logger.error ex.backtrace.join("\n")
        return true # always return true so that failed email doesn't crash app.
      end
    end

    def set_commission
      unless changes.has_key?(:commission_flat_rate)
        self.commission_flat_rate = SpreeDropShip::Config[:default_commission_flat_rate]
      end
      unless changes.has_key?(:commission_percentage)
        self.commission_percentage = SpreeDropShip::Config[:default_commission_percentage]
      end
    end

    def delete_banner
      self.banner = nil
      self.banner_crop = nil
    end

    def delete_profile_image
      self.profile_image = nil
      self.profile_image_crop = nil
    end

    def delete_hero
      self.hero = nil
      self.hero_crop = nil
    end

end
