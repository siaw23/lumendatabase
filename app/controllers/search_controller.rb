# This class abstracts common functionality of Notices::SearchController and
# Entities::SearchController. It is not meant to be used on its own. It should
# be subclassed, and subclasses must define the following:
# - EACH_SERIALIZER
# - URL_ROOT
# - SEARCHED_MODEL
# - item_searcher
# They may also define html_responder.
class SearchController < ApplicationController
  before_action :prevent_impossible_pagination
  before_action :restrict_deep_pagination

  layout 'search'

  EACH_SERIALIZER = nil
  URL_ROOT = nil

  def index
    @searcher = item_searcher
    @searchdata = @searcher.search
    @wrapped_instances = wrap_instances

    respond_to do |format|
      format.html { html_responder }
      format.json { json_renderer }
    end
  end

  private

  def html_responder; end

  def item_searcher; end

  def json_renderer
    # The self.class incantation is necessary to make instances look up their
    # subclass overrides to these constants, rather than pulling in the
    # original definition.
    render(
      json: @wrapped_instances,
      each_serializer: self.class::EACH_SERIALIZER,
      serializer: ActiveModel::ArraySerializer,
      root: self.class::URL_ROOT,
      meta: meta_hash_for(@searchdata)
    )
  end

  # Enrich the activerecord object with search-related metadata for display.
  # Return the enriched instance (or nil, if none was found).
  def augment_instance(instance)
    return unless instance.present?

    result = @searchdata.select { |datum| datum[:_id] == instance.id.to_s }.first

    class << instance
      attr_accessor :_score, :highlight
    end

    instance._score = result[:_score]

    highlights = result[:highlight].presence || []
    instance.highlight = highlights.map { |h| h[1] }.flatten

    instance
  end

  def sort_by(sort_by_param)
    sorting = Sortings.find(sort_by_param)
    sorting.sort_by
  end

  def wrap_instances
    # #records fetches the database instances while maintaining the search
    # response ordering.
    instances = @searchdata.records
    instances.map { |r| augment_instance(r) }
  end

  # Elasticsearch cannot return more than 20_000 results in production (2000
  # pages at 10 results per page).
  def prevent_impossible_pagination
    return if params[:page].to_i < 2000

    render 'shared/_error',
           status: :not_found,
           locals: {
             message: 'Lumen cannot display more than 2000 pages of results.'
           }
  end

  # Deep pagination is expensive for the CPU, so don't let anonymous users
  # do it.
  def restrict_deep_pagination
    return if pagination_allowed?

    render 'shared/_error',
           status: :unauthorized,
           locals: {
             message: 'You must be logged in to see past the first 10 pages ' \
                      'of results. ' \
                      '<a href="https://lumendatabase.org/pages/researchers#key">Request ' \
                      'a research account key</a>.'.html_safe
           }
  end

  def pagination_allowed?
    [user_signed_in?,
     params[:page].to_i < 11,
     request.format.json?].any?
  end
end
