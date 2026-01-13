# frozen_string_literal: true

class NotificationQuery
  attr_reader :user, :guardian

  def initialize(user:, guardian: nil)
    @user = user
    @guardian = guardian || Guardian.new(user)
  end

  def list(limit: 30, offset: 0, types: nil, filter: nil, order: :desc)
    scope = visible_scope
    scope = scope.where(notification_type: types) if types.present?
    scope = apply_read_filter(scope, filter)
    scope.order(created_at: order).offset(offset).limit(limit).to_a
  end

  def prioritized_list(limit: 30, types: nil)
    scope = visible_scope
    scope = with_priority_ordering(scope, deprioritize: types.blank? ? Notification.like_types : [])
    scope = scope.where(notification_type: types) if types.present?
    scope = scope.where.not(notification_type: Notification.like_types) if types.blank? &&
      likes_disabled?
    scope.limit(limit).to_a
  end

  def recent_ids_with_read_status(limit: 20)
    high_priority = visible_scope.where(read: false, high_priority: true)
    rest = visible_scope.where("NOT notifications.high_priority OR notifications.read")

    [high_priority, rest].flat_map { |s| s.order(id: :desc).limit(limit).pluck(:id, :read) }
  end

  def total_count(filter: nil)
    apply_read_filter(visible_scope, filter).count
  end

  def unread_count
    unread_since_seen.limit(User.max_unread_notifications).count
  end

  def unread_high_priority_count
    visible_scope.where(read: false, high_priority: true).count
  end

  def unread_low_priority_count
    unread_since_seen.where(high_priority: false).limit(User.max_unread_notifications).count
  end

  def unread_count_for_type(notification_type, since: nil)
    scope = visible_scope.where(read: false, notification_type:)
    scope = scope.where("notifications.created_at > ?", since) if since
    scope.count
  end

  def grouped_unread_counts
    visible_scope.where(read: false).limit(User::MAX_UNREAD_BACKLOG).group(:notification_type).count
  end

  def new_personal_messages_count
    unread_since_seen.where(notification_type: Notification.types[:private_message]).count
  end

  def max_id(since_id: nil)
    scope = visible_scope
    scope = scope.where("notifications.id > ?", since_id) if since_id
    scope.maximum(:id)
  end

  private

  def visible_scope
    @visible_scope ||=
      Notification
        .where(user:)
        .joins("LEFT JOIN topics t ON t.id = notifications.topic_id")
        .joins("LEFT JOIN categories c ON c.id = t.category_id")
        .where(topic_visibility_sql)
        .where(badge_visibility_sql)
  end

  def unread_since_seen
    visible_scope.where(read: false).where("notifications.id > ?", @user.seen_notification_id)
  end

  def likes_disabled?
    @user.user_option&.likes_notifications_disabled?
  end

  def apply_read_filter(scope, filter)
    case filter
    when :read
      scope.where(read: true)
    when :unread
      scope.where(read: false)
    else
      scope
    end
  end

  def with_priority_ordering(scope, deprioritize: [])
    scope
      .order(Arel.sql("notifications.high_priority AND NOT notifications.read DESC"))
      .order(unread_ordering_sql(deprioritize))
      .order(Arel.sql("notifications.created_at DESC"))
  end

  def unread_ordering_sql(deprioritized_types)
    if deprioritized_types.present?
      DB.sql_fragment(
        "NOT notifications.read AND notifications.notification_type NOT IN (?) DESC",
        deprioritized_types,
      )
    else
      Arel.sql("NOT notifications.read DESC")
    end
  end

  def topic_visibility_sql
    <<~SQL.squish
      notifications.topic_id IS NULL
      OR (
        t.id IS NOT NULL
        AND #{@guardian.is_staff? ? "TRUE" : "t.deleted_at IS NULL"}
        AND (#{regular_topic_sql} OR #{private_message_sql})
      )
    SQL
  end

  def regular_topic_sql
    secure_ids = @user.secure_category_ids
    category_sql =
      (
        if secure_ids.empty?
          "NOT c.read_restricted"
        else
          "(NOT c.read_restricted OR c.id IN (#{secure_ids.join(",")}))"
        end
      )
    "t.archetype = 'regular' AND (c.id IS NULL OR #{category_sql})"
  end

  def private_message_sql
    <<~SQL.squish
      t.archetype = 'private_message'
      AND t.id IN (
        SELECT topic_id FROM topic_allowed_users WHERE user_id = #{@user.id}
        UNION
        SELECT tg.topic_id FROM topic_allowed_groups tg
        JOIN group_users gu ON gu.group_id = tg.group_id AND gu.user_id = #{@user.id}
      )
    SQL
  end

  def badge_visibility_sql
    type = Notification.types[:granted_badge]
    return "notifications.notification_type != #{type}" unless SiteSetting.enable_badges

    <<~SQL.squish
      notifications.notification_type != #{type}
      OR EXISTS (
        SELECT 1 FROM badges
        WHERE badges.id = (notifications.data::json->>'badge_id')::integer AND badges.enabled
      )
    SQL
  end
end
