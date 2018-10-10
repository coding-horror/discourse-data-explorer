require 'rails_helper'

describe DataExplorer::QueryController do
  routes { ::DataExplorer::Engine.routes }

  def response_json
    MultiJson.load(response.body)
  end

  before do
    SiteSetting.data_explorer_enabled = true
  end

  let!(:admin) { log_in_user(Fabricate(:admin)) }

  def make_query(sql, opts = {})
    q = DataExplorer::Query.new
    q.id = Fabrication::Sequencer.sequence("query-id", 1)
    q.name = opts[:name] || "Query number #{q.id}"
    q.description = "A description for query number #{q.id}"
    q.sql = sql
    q.save
    q
  end

  describe "when disabled" do
    before do
      SiteSetting.data_explorer_enabled = false
    end
    it 'denies every request' do
      get :index
      expect(response.body).to be_empty

      get :index, format: :json
      expect(response.status).to eq(404)

      get :schema, format: :json
      expect(response.status).to eq(404)

      get :show, params: { id: 3 }, format: :json
      expect(response.status).to eq(404)

      post :create, params: { id: 3 }, format: :json
      expect(response.status).to eq(404)

      post :run, params: { id: 3 }, format: :json
      expect(response.status).to eq(404)

      put :update, params: { id: 3 }, format: :json
      expect(response.status).to eq(404)

      delete :destroy, params: { id: 3 }, format: :json
      expect(response.status).to eq(404)
    end
  end

  describe "#index" do
    before do
      require_dependency File.expand_path('../../../lib/queries.rb', __FILE__)
    end

    it "behaves nicely with no user created queries" do
      DataExplorer::Query.destroy_all
      get :index, format: :json
      expect(response.status).to eq(200)
      expect(response_json['queries'].count).to eq(Queries.default.count)
    end

    it "shows all available queries in alphabetical order" do
      DataExplorer::Query.destroy_all
      make_query('SELECT 1 as value', name: 'B')
      make_query('SELECT 1 as value', name: 'A')
      get :index, format: :json
      expect(response.status).to eq(200)
      expect(response_json['queries'].length).to eq(Queries.default.count + 2)
      expect(response_json['queries'][0]['name']).to eq('A')
      expect(response_json['queries'][1]['name']).to eq('B')
    end
  end

  describe "#run" do
    let!(:admin) { log_in(:admin) }

    def run_query(id, params = {})
      params = Hash[params.map { |a| [a[0], a[1].to_s] }]
      post :run, params: { id: id, _params: MultiJson.dump(params) }, format: :json
    end
    it "can run queries" do
      q = make_query('SELECT 23 as my_value')
      run_query q.id
      expect(response.status).to eq(200)
      expect(response_json['success']).to eq(true)
      expect(response_json['errors']).to eq([])
      expect(response_json['columns']).to eq(['my_value'])
      expect(response_json['rows']).to eq([[23]])
    end

    it "can process parameters" do
      q = make_query <<~SQL
      -- [params]
      -- int :foo = 34
      SELECT :foo as my_value
      SQL

      run_query q.id, foo: 23
      expect(response.status).to eq(200)
      expect(response_json['errors']).to eq([])
      expect(response_json['success']).to eq(true)
      expect(response_json['columns']).to eq(['my_value'])
      expect(response_json['rows']).to eq([[23]])

      run_query q.id
      expect(response.status).to eq(200)
      expect(response_json['errors']).to eq([])
      expect(response_json['success']).to eq(true)
      expect(response_json['columns']).to eq(['my_value'])
      expect(response_json['rows']).to eq([[34]])

      # 2.3 is not an integer
      run_query q.id, foo: '2.3'
      expect(response.status).to eq(422)
      expect(response_json['errors']).to_not eq([])
      expect(response_json['success']).to eq(false)
      expect(response_json['errors'].first).to match(/ValidationError/)
    end

    it "doesn't allow you to modify the database #1" do
      p = create_post

      q = make_query <<~SQL
      UPDATE posts SET cooked = '<p>you may already be a winner!</p>' WHERE id = #{p.id}
      RETURNING id
      SQL

      run_query q.id
      p.reload

      # Manual Test - comment out the following lines:
      #   DB.exec "SET TRANSACTION READ ONLY"
      #   raise ActiveRecord::Rollback
      # This test should fail on the below check.
      expect(p.cooked).to_not match(/winner/)
      expect(response.status).to eq(422)
      expect(response_json['errors']).to_not eq([])
      expect(response_json['success']).to eq(false)
      expect(response_json['errors'].first).to match(/read-only transaction/)
    end

    it "doesn't allow you to modify the database #2" do
      p = create_post

      q = make_query <<~SQL
        SELECT 1
      )
      SELECT * FROM query;
      RELEASE SAVEPOINT active_record_1;
      SET TRANSACTION READ WRITE;
      UPDATE posts SET cooked = '<p>you may already be a winner!</p>' WHERE id = #{p.id};
      SAVEPOINT active_record_1;
      SET TRANSACTION READ ONLY;
      WITH query AS (
        SELECT 1
      SQL

      run_query q.id
      p.reload

      # Manual Test - change out the following line:
      #
      #  module ::DataExplorer
      #   def self.run_query(...)
      #     if query.sql =~ /;/
      #
      # to
      #
      #     if false && query.sql =~ /;/
      #
      # Afterwards, this test should fail on the below check.
      expect(p.cooked).to_not match(/winner/)
      expect(response.status).to eq(422)
      expect(response_json['errors']).to_not eq([])
      expect(response_json['success']).to eq(false)
      expect(response_json['errors'].first).to match(/semicolon/)
    end

    it "doesn't allow you to lock rows" do
      q = make_query <<~SQL
      SELECT id FROM posts FOR UPDATE
      SQL

      run_query q.id
      expect(response.status).to eq(422)
      expect(response_json['errors']).to_not eq([])
      expect(response_json['success']).to eq(false)
      expect(response_json['errors'].first).to match(/read-only transaction/)
    end

    it "doesn't allow you to create a table" do
      q = make_query <<~SQL
      CREATE TABLE mytable (id serial)
      SQL

      run_query q.id
      expect(response.status).to eq(422)
      expect(response_json['errors']).to_not eq([])
      expect(response_json['success']).to eq(false)
      expect(response_json['errors'].first).to match(/read-only transaction|syntax error/)
    end

    it "doesn't allow you to break the transaction" do
      q = make_query <<~SQL
      COMMIT
      SQL

      run_query q.id
      expect(response.status).to eq(422)
      expect(response_json['errors']).to_not eq([])
      expect(response_json['success']).to eq(false)
      expect(response_json['errors'].first).to match(/syntax error/)

      q.sql = <<~SQL
      )
      SQL

      run_query q.id
      expect(response.status).to eq(422)
      expect(response_json['errors']).to_not eq([])
      expect(response_json['success']).to eq(false)
      expect(response_json['errors'].first).to match(/syntax error/)

      q.sql = <<~SQL
      RELEASE SAVEPOINT active_record_1
      SQL

      run_query q.id
      expect(response.status).to eq(422)
      expect(response_json['errors']).to_not eq([])
      expect(response_json['success']).to eq(false)
      expect(response_json['errors'].first).to match(/syntax error/)
    end

    it "can export data in CSV format" do
      q = make_query('SELECT 23 as my_value')
      post :run, params: { id: q.id, download: 1 }, format: :csv
      expect(response.status).to eq(200)
    end
  end
end
