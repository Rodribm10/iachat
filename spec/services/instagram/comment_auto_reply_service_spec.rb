require 'rails_helper'

RSpec.describe Instagram::CommentAutoReplyService do
  subject(:service) { described_class.new(entry: entry, change: change) }

  let(:account) { create(:account) }
  let!(:channel) { create(:channel_instagram, account: account, instagram_id: '17841437085704434', access_token: 'valid_instagram_token') }
  let(:entry) { { id: channel.instagram_id } }
  let(:change) do
    {
      field: 'comments',
      value: {
        id: '18102348287027064',
        text: comment_text,
        media_id: '18065713253474097'
      }
    }
  end
  let(:comment_text) { 'quiz' }
  let(:processing_key) { 'INSTAGRAM_COMMENT_AUTOREPLY_PROCESSING::18102348287027064' }
  let(:processed_key) { 'INSTAGRAM_COMMENT_AUTOREPLY_PROCESSED::18102348287027064' }

  before do
    allow(Redis::Alfred).to receive(:get).with(processed_key).and_return(nil)
    allow(Redis::Alfred).to receive(:set).with(processing_key, true, nx: true, ex: 5.minutes.to_i).and_return(true)
    allow(Redis::Alfred).to receive(:set).with(processed_key, true, ex: 30.days.to_i).and_return(true)
    allow(Redis::Alfred).to receive(:delete).with(processing_key).and_return(1)

    stub_request(:post, "https://graph.instagram.com/v22.0/#{channel.instagram_id}/messages")
      .with(
        body: {
          recipient: { comment_id: '18102348287027064' },
          message: { text: 'Quer participar do nosso quiz para casais? Segue o link: https://quiz.hoteis1001noites.com.br' }
        }.to_json,
        query: { access_token: 'valid_instagram_token' }
      )
      .to_return(status: 200, body: { message_id: 'dm-message-id' }.to_json, headers: { 'Content-Type' => 'application/json' })

    stub_request(:post, 'https://graph.instagram.com/v22.0/18102348287027064/replies')
      .with(
        body: { message: 'Vou te mandar o link no DM.' }.to_json,
        query: { access_token: 'valid_instagram_token' }
      )
      .to_return(status: 200, body: { id: 'public-reply-id' }.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  it 'sends a private reply and then a public comment reply for the quiz keyword' do
    service.perform

    expect(WebMock).to have_requested(:post, "https://graph.instagram.com/v22.0/#{channel.instagram_id}/messages")
      .with(query: { access_token: 'valid_instagram_token' }).once
    expect(WebMock).to have_requested(:post, 'https://graph.instagram.com/v22.0/18102348287027064/replies')
      .with(query: { access_token: 'valid_instagram_token' }).once
    expect(Redis::Alfred).to have_received(:set).with(processed_key, true, ex: 30.days.to_i)
  end

  context 'when the keyword has different case and punctuation around it' do
    let(:comment_text) { ' QUIZ! ' }

    it 'matches the keyword' do
      service.perform

      expect(WebMock).to have_requested(:post, "https://graph.instagram.com/v22.0/#{channel.instagram_id}/messages")
        .with(query: { access_token: 'valid_instagram_token' }).once
    end
  end

  context 'when the comment contains the keyword with other words' do
    let(:comment_text) { 'quero quiz' }

    it 'does not reply' do
      service.perform

      expect(WebMock).not_to have_requested(:post, "https://graph.instagram.com/v22.0/#{channel.instagram_id}/messages")
      expect(WebMock).not_to have_requested(:post, 'https://graph.instagram.com/v22.0/18102348287027064/replies')
    end
  end

  context 'when the comment was already processed' do
    before do
      allow(Redis::Alfred).to receive(:get).with(processed_key).and_return('true')
    end

    it 'does not reply again' do
      service.perform

      expect(WebMock).not_to have_requested(:post, "https://graph.instagram.com/v22.0/#{channel.instagram_id}/messages")
    end
  end

  context 'when another worker is already processing the comment' do
    before do
      allow(Redis::Alfred).to receive(:set).with(processing_key, true, nx: true, ex: 5.minutes.to_i).and_return(false)
    end

    it 'does not reply' do
      service.perform

      expect(WebMock).not_to have_requested(:post, "https://graph.instagram.com/v22.0/#{channel.instagram_id}/messages")
    end
  end

  context 'when the comment is a reply to another comment' do
    before do
      change[:value][:parent_id] = 'parent-comment-id'
    end

    it 'does not reply' do
      service.perform

      expect(WebMock).not_to have_requested(:post, "https://graph.instagram.com/v22.0/#{channel.instagram_id}/messages")
    end
  end
end
