Rails.application.routes.draw do
  root to: "videos#index"

  defaults export: true do
    resources :composers, only: %i[index show], type: {id: Integer}
    resources :songs, only: %i[index show], type: {id: Integer}
    resources :videos, only: %i[index show], type: {id: Integer}
    # :nodoc:
    get :health, to: "health#show"
  end
end
