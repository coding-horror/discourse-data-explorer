# frozen_string_literal: true

require 'rails_helper'

describe DataExplorerQueryGroupBookmarkable do
  fab!(:admin_user) { Fabricate(:admin) }
  fab!(:user) { Fabricate(:user) }
  fab!(:guardian) { Guardian.new(user) }
  fab!(:group0) { Fabricate(:group) }
  fab!(:group1) { Fabricate(:group) }
  fab!(:group2) { Fabricate(:group) }
  fab!(:group3) { Fabricate(:group) }
  fab!(:query1) { Fabricate(:query, name: "My First Query",
                                    description: "This is the description of my 1st query.",
                                    sql: "Not really important",
                                    user: admin_user) }
  fab!(:query2) { Fabricate(:query, name: "My Second Query",
                                    description: "This is my 2nd query's description.",
                                    sql: "Not really important",
                                    user: admin_user) }

  before do
    SiteSetting.data_explorer_enabled = true
    Bookmark.register_bookmarkable(DataExplorerQueryGroupBookmarkable)
  end

  # Groups 0 and 1 have access to the Query 1.
  let!(:query_group1) { Fabricate(:query_group, query: query1, group: group0) }
  let!(:query_group2) { Fabricate(:query_group, query: query1, group: group1) }
  # User is member of both groups.
  let!(:group_user1) { Fabricate(:group_user, user: user, group: group0) }
  let!(:group_user2) { Fabricate(:group_user, user: user, group: group1) }

  # Group 1 also has access to query2.
  let!(:query_group3) { Fabricate(:query_group, query: query2, group: group1) }

  # Group 2 has access to query 1. User is NOT a member of this group.
  let!(:query_group4) { Fabricate(:query_group, query: query1, group: group2) }

  # User is a member of Group 3, which has no access to Query 1.
  let!(:group_user3) { Fabricate(:group_user, user: user, group: group3) }

  # User bookmarked the same Query 1 twice, from different Groups (0 and 1)
  let!(:bookmark1) { Fabricate(:bookmark, user: user,
                                          bookmarkable: query_group1,
                                          name: "something i gotta do") }
  let!(:bookmark2) { Fabricate(:bookmark, user: user,
                                          bookmarkable: query_group2,
                                          name: "something else i have to do") }

  # User also bookmarked Query 2 from Group 1.
  let!(:bookmark3) { Fabricate(:bookmark, user: user,
                                          bookmarkable: query_group3,
                                          name: "this is the other query I needed.") }

  # User previously bookmarked Query 1 from Group 2, of which she is no longer a member.
  let!(:bookmark4) { Fabricate(:bookmark, user: user,
                                          bookmarkable: query_group4,
                                          name: "something i gotta do also") }

  subject { RegisteredBookmarkable.new(DataExplorerQueryGroupBookmarkable) }

  describe "#perform_list_query" do
    it "returns all the user's bookmarks" do
      expect(subject.perform_list_query(user, guardian).map(&:id)).to match_array([bookmark1.id, bookmark2.id, bookmark3.id])
    end

    it "does not return bookmarks made from groups that the user is no longer a member of" do
      expect(subject.perform_list_query(user, guardian).map(&:id)).not_to include(bookmark4.id)

      # remove user from the other groups from which they bookmarked a query
      group_user1.delete
      group_user2.delete

      # bookmarks is now empty, because user is not a member of any Groups with permission to see the query
      expect(subject.perform_list_query(user, guardian)).to be_empty
    end

  end

  describe "#perform_search_query" do
    before do
      SearchIndexer.enable
    end

    it "returns bookmarks that match by name" do
      ts_query = Search.ts_query(term: "gotta", ts_config: "simple")
      expect(subject.perform_search_query(subject.perform_list_query(user, guardian), "%gotta%", ts_query).map(&:id)).to match_array([bookmark1.id])
    end

    it "returns bookmarks that match by Query name" do
      ts_query = Search.ts_query(term: "First", ts_config: "simple")
      expect(subject.perform_search_query(subject.perform_list_query(user, guardian), "%First%", ts_query).map(&:id)).to match_array([bookmark1.id, bookmark2.id])
    end

  end

  describe "#can_send_reminder?" do
    it "cannot send the reminder if the group is revoked access to the query" do
      expect(subject.can_send_reminder?(bookmark1)).to eq(true)
      bookmark1.bookmarkable.delete
      bookmark1.reload
      expect(subject.can_send_reminder?(bookmark1)).to eq(false)
    end
  end

  describe "#reminder_handler" do
    it "creates a notification for the user with the correct details" do
      expect { subject.send_reminder_notification(bookmark1) }.to change { Notification.count }.by(1)
      notif = user.notifications.last
      expect(notif.notification_type).to eq(Notification.types[:bookmark_reminder])
      expect(notif.data).to eq(
        {
          title: bookmark1.bookmarkable.query.name,
          bookmarkable_url: "/g/#{bookmark1.bookmarkable.group.name}/reports/#{bookmark1.bookmarkable.query.id}",
          display_username: bookmark1.user.username,
          bookmark_name: bookmark1.name,
          bookmark_id: bookmark1.id
        }.to_json
      )
    end
  end

  describe "#can_see?" do
    it "returns false if the user is not a member of the group from which they created the bookmark" do
      expect(subject.can_see?(guardian, bookmark1)).to eq(true) #Query 1, Group 0
      expect(subject.can_see?(guardian, bookmark2)).to eq(true) #Query 1, Group 1
      expect(subject.can_see?(guardian, bookmark3)).to eq(true) #Query 2, Group 1
      expect(subject.can_see?(guardian, bookmark4)).to eq(false) #Query 1, Group 2

      # remove from Groups 0 and 1
      group_user1.delete # Group 0
      group_user2.delete # Group 1
      guardian.user.reload

      expect(subject.can_see?(guardian, bookmark1)).to eq(false)
      expect(subject.can_see?(guardian, bookmark2)).to eq(false)
      expect(subject.can_see?(guardian, bookmark3)).to eq(false)
      expect(subject.can_see?(guardian, bookmark4)).to eq(false)

      # And adding the user back to the group, just to be sure.
      Fabricate(:group_user, user: user, group: group2)
      guardian.user.reload

      expect(subject.can_see?(guardian, bookmark4)).to eq(true)
    end

  end
end
