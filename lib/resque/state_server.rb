require 'resque/server'
require 'resque-state'

module Resque
  ## Resque Server plugin for Resque Status
  module StateServer
    VIEW_PATH = File.join(File.dirname(__FILE__), 'server', 'views')
    PER_PAGE = 50

    def self.registered(app)
      app.get '/state' do
        @start = params[:start].to_i
        @end = @start + (params[:per_page] || per_page) - 1
        @statuses = Resque::Plugins::State::Hash.statuses(@start, @end)
        @size = Resque::Plugins::State::Hash.count
        status_view(:statuses)
      end

      app.get '/state/:id.js' do
        @status = Resque::Plugins::State::Hash.get(params[:id])
        content_type :js
        @status.json
      end

      app.get '/state/:id' do
        @status = Resque::Plugins::State::Hash.get(params[:id])
        status_view(:status)
      end

      app.post '/state/:id/kill' do
        Resque::Plugins::State::Hash.kill(params[:id])
        redirect u(:statuses)
      end

      app.post '/state/clear' do
        Resque::Plugins::State::Hash.clear
        redirect u(:statuses)
      end

      app.post '/state/clear/completed' do
        Resque::Plugins::State::Hash.clear_completed
        redirect u(:statuses)
      end

      app.post '/state/clear/failed' do
        Resque::Plugins::State::Hash.clear_failed
        redirect u(:statuses)
      end

      app.get '/state.poll' do
        content_type 'text/plain'
        @polling = true

        @start = params[:start].to_i
        @end = @start + (params[:per_page] || per_page) - 1
        @statuses = Resque::Plugins::State::Hash.statuses(@start, @end)
        @size = Resque::Plugins::State::Hash.count
        status_view(:statuses, layout: false)
      end

      app.helpers do
        def per_page
          PER_PAGE
        end

        def status_view(filename, options = {}, locals = {})
          erb(File.read(File.join(::Resque::StateServer::VIEW_PATH, "#{filename}.erb")), options, locals)
        end

        def status_poll(start)
          if @polling
            text = "Last Updated: #{Time.now.strftime('%H:%M:%S')}"
          else
            text = "<a href='#{u(request.path_info)}.poll?start=#{start}' rel='poll'>Live Poll</a>"
          end
          "<p class='poll'>#{text}</p>"
        end
      end

      app.tabs << 'State'
    end
  end
end

Resque::Server.register Resque::StateServer
