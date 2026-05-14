class OverdueNotifierMailer < Mailer
  def overdue_notification(user, issue)
    @user = user
    @issue = issue

    mail(
      to: user.mail,
      subject: l(:text_overdue_issue_subject, issue: issue.subject, id: issue.id)
    ) do |format|
      format.text
    end
  end
end

