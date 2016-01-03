require 'iron_worker_ng'
require 'mailgun'
require 'csv'
require 'plivo'
include Plivo
# ##Global object for further stuff #####
$MG_CLIENT = Mailgun::Client.new(ENV['MAILGUN_API'])
$PLIVO_CLIENT = RestAPI.new(ENV['PLIVO_AUTH_ID'], ENV['PLIVO_AUTH_TOKEN'])
CC = '+91' # Country Code for India
##########################################

########### [Deprecreated] - Function calls for offloading background processing to Iron ######
# Send bulk sms along with email for high priority stuff
def send_bulk_sms(message)
  client = IronWorkerNG::Client.new
  client.tasks.create('master_email', payload)
  payload = {}
  payload['message'] = message
  client.tasks.create('master_sms', payload)
end

# Method to send bulk email

def send_bulk_email(message, subject = 'Notification')
  client = IronWorkerNG::Client.new
  payload = {}
  payload['message'] = message
  payload['Subject'] = subject
end
#################################################################################################

##### Functions for email communication###########

####### Single email for Auto-Confirmation
def send_an_email(message, subject, to)
  message_params = {}
  message_params[:from] = 'QuikSort Bot <***@quiksort.in>'
  message_params[:to] = to
  message_params[:subject] = subject
  message_params[:text] = message
  logger.info $MG_CLIENT.send_message 'quiksort.in', message_params
end

##### Send Batch email
def batch_email(html_message, text_message, attachments, subject = 'Notification')
  logger.info 'Preparing for Batch email sending'
  mb_obj = Mailgun::BatchMessage.new($MG_CLIENT, 'quiksort.in')
  mb_obj.set_from_address('***@quiksort.in', 'first' => 'Quik', 'last' => 'Bot')
  mb_obj.set_subject(subject)
  mb_obj.set_text_body(text_message)
  mb_obj.set_html_body(html_message)
  name = {}
  name['first'] = ''
  name['last'] = ''
  forms = CSV.read('***.csv', headers: true)
  forms.each do |row|
    name['first'] = row['Name']
    mb_obj.add_recipient(:to, row['Email ID'], name)
  end
  unless attachments.empty?
    attachments.each do |attachment|
      mb_obj.add_attachment(File.join(ENV['OPENSHIFT_DATA_DIR'], attachment), attachment)
    end
end
  message_ids = mb_obj.finalize
end

##### Send Batch SMS
def batch_sms(message)
  phone_numbers = []
  forms = CSV.read('***.csv', headers: true)
  forms.each do |row|
    phone_numbers << CC + row['Phone number']
  end
  payload = {
    'src' => 'QKSRT',
    'dst' => phone_numbers.join('<'),
    'text' => message
  }

  response = $PLIVO_CLIENT.send_message(payload)
  logger.info response
end

########################
