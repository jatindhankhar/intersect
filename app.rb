require 'sinatra'
require 'oj'
require 'rest-client'
require 'openssl'
require_relative 'launcher'
# #####Global Variables ##############
$allowed_emails = ['someone@domain.com','anotherone@domain.com'] #Replace with trusted senders
$ZOTIFY_SECRET = ENV['ZOTIFY_SECRET']
$MAILGUN_API = ENV['MAILGUN_API']

######### Utility functions #########
### To download attachments
def get_attachment(url)
  resource = RestClient::Resource.new(url, 'api', $MAILGUN_API)
  resource.get
end

### To verify that payload is from trusted server
def verified?(api_key, token, timestamp, signature)
  digest = OpenSSL::Digest::SHA256.new
  data = [timestamp, token].join
  signature == OpenSSL::HMAC.hexdigest(digest, api_key, data)
end
#####################################
### HTTP Verb Logic ############
get '/' do
  "This is where magic happens"
end

post '/inbound' do
  sender = params['sender'] # Don't use from parameter
  subject = params['subject'].gsub /\s+/, '' # Removes space anywhere
  body = params['stripped-text']
  logger.info sender
  logger.info subject
  logger.info body
  ##########################
  if verified?($MAILGUN_API, params['token'], params['timestamp'], params['signature'])
    logger.info 'Verfied server'
    if $allowed_emails.include? sender
      logger.info 'Trusted sender'
      if subject.upcase == 'SMS'
        batch_sms body
        body_reply = 'Thank you. Your message has been queued'
        send_an_email(body_reply, 'QuikBot : Auto-Confirmation for message ', sender)
      elsif (subject.upcase == 'EMAIL') || (subject.upcase == 'E-MAIL')
        files = []
        if params.key?('attachments')
          attachments = Oj.load(params['attachments'])
          attachments.each do |attachment|
            logger.info "Url is #{attachment['url']}"
            logger.info "Name is #{attachment['name']}"
            IO.write(File.join(ENV['OPENSHIFT_DATA_DIR'], attachment['name']), get_attachment(attachment['url']))
            files << attachment['name']
          end
       end
        logger.info files
        batch_email(params['body-html'], params['body-plain'], files)
        body_reply = 'Thank You. Your message has been queued'
        send_an_email(body_reply, 'QuikBot : Auto-Confirmation for message ', sender)
        ##### Cleaning up the attachments ##########
        files.each do |file_name|
          target_file = File.join(ENV['OPENSHIFT_DATA_DIR'], file_name)
          File.delete target_file if File.file?(target_file) && File.exist?(target_file)
        end
        ############################################
      else
        # Notify user to
        subject_reply = 'Use of a Non-Legit Subject'
        body_reply = "Dear User,\n You tried to send a message with the subject **#{subject}**. Allowed subjects are Email and SMS, depending on the mode of delivery.\nThanks, QuikBot "
        send_an_email(body_reply, subject_reply, sender)
        end

    else
      # Notify to STFU
      logger.info "Unknown user with email id #{sender}"
     end
  else
    logger.info "Attempt for spoofed request from #{request.ip}"
 end
end

post '/zotify' do
  if params['api_key'] == $ZOTIFY_SECRET
    priority = params['priority'].to_i
    if priority == 1
      body = "#{parmas[author]}\n#{params['description']}"
      body = body[0..155] + ' ...' if body.length > 160 # Truncate message with ... if greater than SMS length
      send_bulk_sms body
    else
      # Email
      subject = params['title']
      description = params['description']
      author = params['author']
      body = "#{params['course']} : #{author} posted via Zotify\n#{description}"
      send_bulk_email body, subject
    end
  else
    'Unauthorized access or expired api key :|'
  end
end
