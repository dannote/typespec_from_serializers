Rails.application.routes.draw do
  root to: "videos#index"

  defaults export: true do
    resources :composers, only: %i[index show], type: {id: Integer}
    resources :songs, only: %i[index show], type: {id: Integer} do
      collection do
        post :search
      end
    end
    resources :videos, only: %i[index show], type: {id: Integer}
    resources :tasks, only: %i[index show], type: {id: Integer} do
      resources :comments, only: %i[index create], type: {task_id: Integer, id: Integer}
    end
    # :nodoc:
    get :health, to: "health#show"
  end
end
