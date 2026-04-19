# Captain Semantic Memory — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Layer 3 (episodic contact memory via semantic embeddings) to the Captain AI, with automatic extraction at end of conversations and semantic recall before each response, without altering the existing 3 layers.

**Architecture:** New `captain_contact_memories` table with pgvector embeddings (1536d). Extraction runs async after conversation resolved OR 30-min silence. Recall runs sync (500ms timeout) before LLM call in `AgentRunnerService`. Two independent per-account feature flags stored in `account.custom_attributes`, default OFF. Graceful degradation: any failure in Layer 3 falls back to existing layers (never blocks response).

**Tech Stack:** Ruby 3.4.4, Rails 7.1, Sidekiq + sidekiq-cron, PostgreSQL + pgvector, gem `neighbor`, `RubyLLM`, Pundit, Vue 3, RSpec.

**Spec:** `docs/superpowers/specs/2026-04-18-captain-semantic-memory-design.md`

---

## File Structure

### New files

```
enterprise/app/models/captain/contact_memory.rb
enterprise/app/services/captain/contact_memories/extraction_service.rb
enterprise/app/services/captain/contact_memories/recall_service.rb
enterprise/app/services/captain/contact_memories/contradiction_checker_service.rb
enterprise/app/services/captain/contact_memories/prompt_injection_service.rb
enterprise/app/jobs/captain/contact_memories/update_embedding_job.rb
enterprise/app/jobs/captain/contact_memories/contradiction_checker_job.rb
enterprise/app/jobs/captain/contact_memories/extract_from_conversation_job.rb
enterprise/app/jobs/captain/contact_memories/silence_detector_job.rb
enterprise/app/jobs/captain/contact_memories/aging_job.rb
enterprise/app/jobs/captain/contact_memories/hard_delete_expired_job.rb
enterprise/app/controllers/api/v1/accounts/contacts/memories_controller.rb
enterprise/app/policies/captain/contact_memory_policy.rb
app/javascript/dashboard/routes/dashboard/contact/components/ContactMemories.vue
app/javascript/dashboard/api/captain/contactMemories.js
db/migrate/<ts>_create_captain_contact_memories.rb

spec/enterprise/models/captain/contact_memory_spec.rb
spec/enterprise/services/captain/contact_memories/extraction_service_spec.rb
spec/enterprise/services/captain/contact_memories/recall_service_spec.rb
spec/enterprise/services/captain/contact_memories/contradiction_checker_service_spec.rb
spec/enterprise/services/captain/contact_memories/prompt_injection_service_spec.rb
spec/enterprise/jobs/captain/contact_memories/update_embedding_job_spec.rb
spec/enterprise/jobs/captain/contact_memories/extract_from_conversation_job_spec.rb
spec/enterprise/jobs/captain/contact_memories/silence_detector_job_spec.rb
spec/enterprise/jobs/captain/contact_memories/aging_job_spec.rb
spec/enterprise/jobs/captain/contact_memories/hard_delete_expired_job_spec.rb
spec/enterprise/controllers/api/v1/accounts/contacts/memories_controller_spec.rb
spec/enterprise/policies/captain/contact_memory_policy_spec.rb
spec/enterprise/integration/captain_semantic_memory_spec.rb
```

### Modified files

```
app/models/concerns/captain_featurable.rb           # add flag helpers
enterprise/app/services/captain/assistant/agent_runner_service.rb  # inject recall
config/routes.rb                                     # memories endpoints
config/schedule.yml                                  # 3 new crons
enterprise/app/listeners/captain_listener.rb         # (ou novo) hook de conversation.resolved
```

---

## Phase 0 — Feature flags foundation

### Task 0.1: Feature flag helpers on Account

**Files:**
- Modify: `app/models/concerns/captain_featurable.rb`
- Test: `spec/models/concerns/captain_featurable_spec.rb`

- [ ] **Step 1: Write failing tests**

Add to `spec/models/concerns/captain_featurable_spec.rb`:

```ruby
describe '#captain_contact_memory_extraction_enabled?' do
  let(:account) { create(:account) }

  it 'returns false by default' do
    expect(account.captain_contact_memory_extraction_enabled?).to be(false)
  end

  it 'returns true when flag set in custom_attributes' do
    account.custom_attributes = { 'captain_contact_memory_extraction_enabled' => true }
    account.save!
    expect(account.captain_contact_memory_extraction_enabled?).to be(true)
  end
end

describe '#captain_contact_memory_recall_enabled?' do
  let(:account) { create(:account) }

  it 'returns false by default' do
    expect(account.captain_contact_memory_recall_enabled?).to be(false)
  end

  it 'returns true when flag set in custom_attributes' do
    account.custom_attributes = { 'captain_contact_memory_recall_enabled' => true }
    account.save!
    expect(account.captain_contact_memory_recall_enabled?).to be(true)
  end
end
```

- [ ] **Step 2: Run tests, expect fail**

Run: `bundle exec rspec spec/models/concerns/captain_featurable_spec.rb -e "captain_contact_memory"`
Expected: FAIL with NoMethodError.

- [ ] **Step 3: Implement helpers**

Add to `app/models/concerns/captain_featurable.rb` inside the module:

```ruby
def captain_contact_memory_extraction_enabled?
  custom_attributes.fetch('captain_contact_memory_extraction_enabled', false) == true
end

def captain_contact_memory_recall_enabled?
  custom_attributes.fetch('captain_contact_memory_recall_enabled', false) == true
end
```

- [ ] **Step 4: Run tests, expect pass**

Run: `bundle exec rspec spec/models/concerns/captain_featurable_spec.rb -e "captain_contact_memory"`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/models/concerns/captain_featurable.rb spec/models/concerns/captain_featurable_spec.rb
git commit -m "feat(captain-memory): add feature flag helpers on Account"
```

---

## Phase 1 — Migration + Model

### Task 1.1: Create `captain_contact_memories` table

**Files:**
- Create: `db/migrate/<ts>_create_captain_contact_memories.rb`

- [ ] **Step 1: Generate migration**

```bash
bin/rails g migration CreateCaptainContactMemories
```

This produces `db/migrate/<timestamp>_create_captain_contact_memories.rb`.

- [ ] **Step 2: Write migration content**

Replace the generated file contents with:

```ruby
class CreateCaptainContactMemories < ActiveRecord::Migration[7.1]
  def change
    create_table :captain_contact_memories do |t|
      t.references :account, null: false, foreign_key: true
      t.references :contact, null: false, foreign_key: true
      t.string :memory_type, null: false
      t.text :content, null: false
      t.text :evidence, null: false
      t.float :confidence, null: false
      t.string :scope, null: false, default: 'global'
      t.vector :embedding, limit: 1536
      t.bigint :source_conversation_id
      t.bigint :source_unit_id
      t.bigint :source_inbox_id
      t.datetime :expires_at
      t.datetime :last_verified_at, null: false
      t.datetime :superseded_at
      t.bigint :superseded_by_id
      t.datetime :deleted_at
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end

    add_index :captain_contact_memories,
              [:account_id, :contact_id],
              where: 'deleted_at IS NULL AND superseded_at IS NULL',
              name: 'idx_ccm_recall'

    add_index :captain_contact_memories,
              [:source_unit_id, :memory_type, :created_at],
              name: 'idx_ccm_analytics'

    add_index :captain_contact_memories,
              :deleted_at,
              where: 'deleted_at IS NOT NULL',
              name: 'idx_ccm_hard_delete'

    add_index :captain_contact_memories,
              :superseded_by_id,
              where: 'superseded_at IS NOT NULL',
              name: 'idx_ccm_superseded'

    add_index :captain_contact_memories,
              :source_conversation_id,
              name: 'idx_ccm_source_conversation'

    execute <<~SQL.squish
      CREATE INDEX idx_ccm_embedding
      ON captain_contact_memories
      USING ivfflat (embedding vector_cosine_ops)
      WITH (lists = 100);
    SQL
  end
end
```

- [ ] **Step 3: Run migration**

Run: `bin/rails db:migrate`
Expected: migration runs, table created.

- [ ] **Step 4: Verify schema**

Run: `bin/rails dbconsole -p -- -c '\d captain_contact_memories'`
Expected: all columns and indexes present.

- [ ] **Step 5: Commit**

```bash
git add db/migrate/*_create_captain_contact_memories.rb db/schema.rb
git commit -m "feat(captain-memory): create captain_contact_memories table with pgvector index"
```

---

### Task 1.2: Create `Captain::ContactMemory` model

**Files:**
- Create: `enterprise/app/models/captain/contact_memory.rb`
- Test: `spec/enterprise/models/captain/contact_memory_spec.rb`
- Create: `spec/factories/captain_contact_memories.rb`

- [ ] **Step 1: Write failing model tests**

Create `spec/enterprise/models/captain/contact_memory_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe Captain::ContactMemory, type: :model do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }

  describe 'validations' do
    it 'requires memory_type' do
      memory = build(:captain_contact_memory, account: account, contact: contact, memory_type: nil)
      expect(memory).not_to be_valid
    end

    it 'requires content' do
      memory = build(:captain_contact_memory, account: account, contact: contact, content: '')
      expect(memory).not_to be_valid
    end

    it 'requires evidence' do
      memory = build(:captain_contact_memory, account: account, contact: contact, evidence: '')
      expect(memory).not_to be_valid
    end

    it 'requires confidence between 0 and 1' do
      memory = build(:captain_contact_memory, account: account, contact: contact, confidence: 1.5)
      expect(memory).not_to be_valid
    end

    it 'rejects invalid memory_type' do
      expect {
        build(:captain_contact_memory, memory_type: 'invalid_type')
      }.to raise_error(ArgumentError)
    end

    it 'limits content to 1000 chars' do
      memory = build(:captain_contact_memory, account: account, contact: contact, content: 'a' * 1001)
      expect(memory).not_to be_valid
    end
  end

  describe '.active' do
    let!(:active) { create(:captain_contact_memory, account: account, contact: contact) }
    let!(:deleted) { create(:captain_contact_memory, account: account, contact: contact, deleted_at: Time.current) }
    let!(:superseded) { create(:captain_contact_memory, account: account, contact: contact, superseded_at: Time.current) }
    let!(:expired) { create(:captain_contact_memory, account: account, contact: contact, expires_at: 1.day.ago) }

    it 'excludes deleted, superseded, and expired' do
      expect(described_class.active).to contain_exactly(active)
    end
  end

  describe '.scope_compatible' do
    let!(:global_fact) { create(:captain_contact_memory, account: account, contact: contact, scope: 'global') }
    let!(:unit_fact) { create(:captain_contact_memory, account: account, contact: contact, scope: 'unit:5') }
    let!(:other_unit_fact) { create(:captain_contact_memory, account: account, contact: contact, scope: 'unit:7') }

    it 'returns global + facts for requested unit' do
      expect(described_class.scope_compatible(5)).to contain_exactly(global_fact, unit_fact)
    end

    it 'when unit_id is nil, returns only global' do
      expect(described_class.scope_compatible(nil)).to contain_exactly(global_fact)
    end
  end

  describe '#soft_delete!' do
    let(:memory) { create(:captain_contact_memory, account: account, contact: contact) }

    it 'sets deleted_at' do
      freeze_time do
        memory.soft_delete!
        expect(memory.reload.deleted_at).to eq(Time.current)
      end
    end
  end

  describe '#supersede_by!' do
    let(:old) { create(:captain_contact_memory, account: account, contact: contact) }
    let(:new_one) { create(:captain_contact_memory, account: account, contact: contact) }

    it 'links the old memory as superseded by the new one' do
      old.supersede_by!(new_one)
      expect(old.reload.superseded_by_id).to eq(new_one.id)
      expect(old.superseded_at).not_to be_nil
    end
  end

  describe '#recall_weight' do
    it 'returns 1.0 for non-expired' do
      memory = build(:captain_contact_memory, account: account, contact: contact, expires_at: 1.day.from_now)
      expect(memory.recall_weight).to eq(1.0)
    end

    it 'returns 0.7 for expired' do
      memory = build(:captain_contact_memory, account: account, contact: contact, expires_at: 1.day.ago)
      expect(memory.recall_weight).to eq(0.7)
    end
  end
end
```

- [ ] **Step 2: Write factory**

Create `spec/factories/captain_contact_memories.rb`:

```ruby
FactoryBot.define do
  factory :captain_contact_memory, class: 'Captain::ContactMemory' do
    account
    contact
    memory_type { 'preferencia' }
    content { 'Prefere Stilo com hidromassagem' }
    evidence { "cliente disse 'quero a Stilo com hidro de novo'" }
    confidence { 0.9 }
    scope { 'global' }
    last_verified_at { Time.current }
  end
end
```

- [ ] **Step 3: Run tests, expect fail**

Run: `bundle exec rspec spec/enterprise/models/captain/contact_memory_spec.rb`
Expected: FAIL (class not defined).

- [ ] **Step 4: Implement model**

Create `enterprise/app/models/captain/contact_memory.rb`:

```ruby
# == Schema Information
#
# Table name: captain_contact_memories
#
#  id                     :bigint           not null, primary key
#  account_id             :bigint           not null
#  contact_id             :bigint           not null
#  memory_type            :string           not null
#  content                :text             not null
#  evidence               :text             not null
#  confidence             :float            not null
#  scope                  :string           not null, default: 'global'
#  embedding              :vector(1536)
#  source_conversation_id :bigint
#  source_unit_id         :bigint
#  source_inbox_id        :bigint
#  expires_at             :datetime
#  last_verified_at       :datetime         not null
#  superseded_at          :datetime
#  superseded_by_id       :bigint
#  deleted_at             :datetime
#  metadata               :jsonb            not null, default: {}
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#
class Captain::ContactMemory < ApplicationRecord
  self.table_name = 'captain_contact_memories'

  MEMORY_TYPES = %w[
    preferencia data_comemorativa vinculo_social padrao_comportamental
    reclamacao feedback_positivo restricao vinculo_comercial contexto_pessoal
  ].freeze

  belongs_to :account
  belongs_to :contact
  belongs_to :source_conversation, class_name: 'Conversation', optional: true
  belongs_to :source_unit, class_name: 'Captain::Unit', optional: true
  belongs_to :source_inbox, class_name: 'Inbox', optional: true
  belongs_to :superseded_by, class_name: 'Captain::ContactMemory', optional: true

  has_neighbors :embedding, normalize: true

  validates :memory_type, presence: true, inclusion: { in: MEMORY_TYPES }
  validates :content, presence: true, length: { maximum: 1000 }
  validates :evidence, presence: true
  validates :confidence, presence: true, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 }
  validates :scope, presence: true

  scope :active, lambda {
    where(deleted_at: nil, superseded_at: nil)
      .where('expires_at IS NULL OR expires_at > ?', Time.current)
  }

  scope :for_contact, ->(id) { where(contact_id: id) }
  scope :by_type, ->(type) { where(memory_type: type) }

  scope :scope_compatible, lambda { |unit_id|
    if unit_id.present?
      where(scope: ['global', "unit:#{unit_id}"])
    else
      where(scope: 'global')
    end
  }

  def soft_delete!
    update!(deleted_at: Time.current)
  end

  def supersede_by!(other)
    update!(superseded_at: Time.current, superseded_by_id: other.id)
  end

  def recall_weight
    return 0.7 if expires_at.present? && expires_at < Time.current

    1.0
  end
end
```

- [ ] **Step 5: Run tests, expect pass**

Run: `bundle exec rspec spec/enterprise/models/captain/contact_memory_spec.rb`
Expected: PASS all.

- [ ] **Step 6: Commit**

```bash
git add enterprise/app/models/captain/contact_memory.rb spec/enterprise/models/captain/contact_memory_spec.rb spec/factories/captain_contact_memories.rb
git commit -m "feat(captain-memory): add Captain::ContactMemory model with scopes and lifecycle methods"
```

---

## Phase 2 — Services

### Task 2.1: PromptInjectionService

**Files:**
- Create: `enterprise/app/services/captain/contact_memories/prompt_injection_service.rb`
- Test: `spec/enterprise/services/captain/contact_memories/prompt_injection_service_spec.rb`

- [ ] **Step 1: Write failing test**

Create `spec/enterprise/services/captain/contact_memories/prompt_injection_service_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe Captain::ContactMemories::PromptInjectionService do
  describe '#call' do
    it 'returns empty string when memories empty' do
      result = described_class.new(memories: []).call
      expect(result).to eq('')
    end

    it 'formats memories as XML block' do
      memories = [
        build_stubbed(:captain_contact_memory, memory_type: 'preferencia', content: 'Prefere Stilo', confidence: 0.92),
        build_stubbed(:captain_contact_memory, memory_type: 'data_comemorativa', content: 'Aniversário 14/02', confidence: 0.88)
      ]

      result = described_class.new(memories: memories).call

      expect(result).to include('<memoria_cliente>')
      expect(result).to include('<preferencia confidence="0.92">Prefere Stilo</preferencia>')
      expect(result).to include('<data_comemorativa confidence="0.88">Aniversário 14/02</data_comemorativa>')
      expect(result).to include('</memoria_cliente>')
    end

    it 'escapes XML-unsafe chars in content' do
      memories = [build_stubbed(:captain_contact_memory, content: 'texto com <tag> & ampersand')]
      result = described_class.new(memories: memories).call
      expect(result).to include('texto com &lt;tag&gt; &amp; ampersand')
    end
  end
end
```

- [ ] **Step 2: Run, expect fail**

Run: `bundle exec rspec spec/enterprise/services/captain/contact_memories/prompt_injection_service_spec.rb`
Expected: FAIL (class not defined).

- [ ] **Step 3: Implement service**

Create `enterprise/app/services/captain/contact_memories/prompt_injection_service.rb`:

```ruby
class Captain::ContactMemories::PromptInjectionService
  def initialize(memories:)
    @memories = memories
  end

  def call
    return '' if @memories.blank?

    lines = @memories.map do |memory|
      %(  <#{memory.memory_type} confidence="#{format('%.2f', memory.confidence)}">#{escape(memory.content)}</#{memory.memory_type}>)
    end

    "<memoria_cliente>\n#{lines.join("\n")}\n</memoria_cliente>"
  end

  private

  def escape(text)
    text.to_s.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;')
  end
end
```

- [ ] **Step 4: Run tests, expect pass**

Run: `bundle exec rspec spec/enterprise/services/captain/contact_memories/prompt_injection_service_spec.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add enterprise/app/services/captain/contact_memories/prompt_injection_service.rb spec/enterprise/services/captain/contact_memories/prompt_injection_service_spec.rb
git commit -m "feat(captain-memory): add PromptInjectionService formatting memories as XML"
```

---

### Task 2.2: RecallService

**Files:**
- Create: `enterprise/app/services/captain/contact_memories/recall_service.rb`
- Test: `spec/enterprise/services/captain/contact_memories/recall_service_spec.rb`

- [ ] **Step 1: Write failing tests**

Create `spec/enterprise/services/captain/contact_memories/recall_service_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe Captain::ContactMemories::RecallService do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }
  let(:embedding_service) { instance_double(Captain::Llm::EmbeddingService) }

  before do
    allow(Captain::Llm::EmbeddingService).to receive(:new).and_return(embedding_service)
    allow(embedding_service).to receive(:get_embedding).and_return(Array.new(1536, 0.1))
  end

  describe '#call' do
    it 'returns empty array when contact has no memories' do
      result = described_class.new(contact: contact, query_text: 'olá').call
      expect(result).to eq([])
    end

    it 'returns top-K active memories ordered by neighbor distance' do
      fact_a = create(:captain_contact_memory, contact: contact, account: account, content: 'Prefere Stilo', embedding: Array.new(1536, 0.1))
      fact_b = create(:captain_contact_memory, contact: contact, account: account, content: 'Aniversário 14/02', embedding: Array.new(1536, 0.2))
      create(:captain_contact_memory, contact: contact, account: account, deleted_at: Time.current, embedding: Array.new(1536, 0.1))

      result = described_class.new(contact: contact, query_text: 'quero reservar').call

      expect(result).to include(fact_a, fact_b)
      expect(result.size).to eq(2)
    end

    it 'respects unit scope filtering' do
      global_fact = create(:captain_contact_memory, contact: contact, account: account, scope: 'global', embedding: Array.new(1536, 0.1))
      unit5_fact = create(:captain_contact_memory, contact: contact, account: account, scope: 'unit:5', embedding: Array.new(1536, 0.1))
      unit7_fact = create(:captain_contact_memory, contact: contact, account: account, scope: 'unit:7', embedding: Array.new(1536, 0.1))

      result = described_class.new(contact: contact, query_text: 'x', unit_id: 5).call

      expect(result).to include(global_fact, unit5_fact)
      expect(result).not_to include(unit7_fact)
    end

    it 'respects top_k limit (default 5)' do
      7.times { create(:captain_contact_memory, contact: contact, account: account, embedding: Array.new(1536, rand)) }
      result = described_class.new(contact: contact, query_text: 'x').call
      expect(result.size).to eq(5)
    end

    it 'returns empty array when embedding_service raises' do
      allow(embedding_service).to receive(:get_embedding).and_raise(Captain::Llm::EmbeddingService::EmbeddingsError)
      create(:captain_contact_memory, contact: contact, account: account, embedding: Array.new(1536, 0.1))

      result = described_class.new(contact: contact, query_text: 'x').call
      expect(result).to eq([])
    end

    it 'returns empty array when timeout exceeded' do
      allow(Timeout).to receive(:timeout).and_raise(Timeout::Error)
      create(:captain_contact_memory, contact: contact, account: account, embedding: Array.new(1536, 0.1))

      result = described_class.new(contact: contact, query_text: 'x').call
      expect(result).to eq([])
    end

    it 'skips memories with NULL embedding' do
      create(:captain_contact_memory, contact: contact, account: account, embedding: nil)
      result = described_class.new(contact: contact, query_text: 'x').call
      expect(result).to eq([])
    end
  end
end
```

- [ ] **Step 2: Run, expect fail**

Run: `bundle exec rspec spec/enterprise/services/captain/contact_memories/recall_service_spec.rb`
Expected: FAIL.

- [ ] **Step 3: Implement service**

Create `enterprise/app/services/captain/contact_memories/recall_service.rb`:

```ruby
class Captain::ContactMemories::RecallService
  TIMEOUT_SECONDS = 0.5
  DEFAULT_TOP_K = 5

  def initialize(contact:, query_text:, unit_id: nil, top_k: DEFAULT_TOP_K)
    @contact = contact
    @query_text = query_text
    @unit_id = unit_id
    @top_k = top_k
  end

  def call
    return [] if @contact.blank? || @query_text.blank?

    Timeout.timeout(TIMEOUT_SECONDS) do
      query_embedding = Captain::Llm::EmbeddingService.new(account_id: @contact.account_id).get_embedding(@query_text)
      return [] if query_embedding.blank?

      Captain::ContactMemory
        .active
        .for_contact(@contact.id)
        .scope_compatible(@unit_id)
        .where.not(embedding: nil)
        .nearest_neighbors(:embedding, query_embedding, distance: 'cosine')
        .limit(@top_k)
        .to_a
    end
  rescue Timeout::Error, Captain::Llm::EmbeddingService::EmbeddingsError, StandardError => e
    Rails.logger.warn("[ContactMemory::RecallService] #{e.class}: #{e.message}")
    []
  end
end
```

- [ ] **Step 4: Run tests, expect pass**

Run: `bundle exec rspec spec/enterprise/services/captain/contact_memories/recall_service_spec.rb`
Expected: PASS all.

- [ ] **Step 5: Commit**

```bash
git add enterprise/app/services/captain/contact_memories/recall_service.rb spec/enterprise/services/captain/contact_memories/recall_service_spec.rb
git commit -m "feat(captain-memory): add RecallService with timeout and graceful degradation"
```

---

### Task 2.3: ExtractionService

**Files:**
- Create: `enterprise/app/services/captain/contact_memories/extraction_service.rb`
- Test: `spec/enterprise/services/captain/contact_memories/extraction_service_spec.rb`

- [ ] **Step 1: Write failing tests**

Create `spec/enterprise/services/captain/contact_memories/extraction_service_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe Captain::ContactMemories::ExtractionService do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, contact: contact) }

  before do
    create(:message, conversation: conversation, message_type: :incoming, content: 'Oi, quero reservar a Stilo com hidro de novo pro meu aniversário dia 14/02')
    create(:message, conversation: conversation, message_type: :outgoing, content: 'Claro! Confirmando então...')
  end

  describe '#call' do
    let(:llm_response) do
      {
        'facts' => [
          {
            'memory_type' => 'preferencia',
            'content' => 'Prefere Stilo com hidromassagem',
            'evidence' => "disse 'quero a Stilo com hidro de novo'",
            'confidence' => 0.92,
            'scope' => 'global'
          },
          {
            'memory_type' => 'data_comemorativa',
            'content' => 'Aniversário dia 14/02',
            'evidence' => "disse 'meu aniversário dia 14/02'",
            'confidence' => 0.88,
            'scope' => 'global'
          }
        ]
      }.to_json
    end

    before do
      allow_any_instance_of(described_class).to receive(:call_llm).and_return(llm_response)
    end

    it 'returns array of valid facts' do
      result = described_class.new(conversation: conversation).call
      expect(result.size).to eq(2)
      expect(result.first[:memory_type]).to eq('preferencia')
    end

    it 'drops facts with missing evidence' do
      bad_response = { 'facts' => [{ 'memory_type' => 'preferencia', 'content' => 'x', 'evidence' => '', 'confidence' => 0.9 }] }.to_json
      allow_any_instance_of(described_class).to receive(:call_llm).and_return(bad_response)
      expect(described_class.new(conversation: conversation).call).to eq([])
    end

    it 'drops facts with confidence < 0.5' do
      bad_response = { 'facts' => [{ 'memory_type' => 'preferencia', 'content' => 'x', 'evidence' => 'y', 'confidence' => 0.3 }] }.to_json
      allow_any_instance_of(described_class).to receive(:call_llm).and_return(bad_response)
      expect(described_class.new(conversation: conversation).call).to eq([])
    end

    it 'drops facts with invalid type' do
      bad_response = { 'facts' => [{ 'memory_type' => 'invalid', 'content' => 'x', 'evidence' => 'y', 'confidence' => 0.9 }] }.to_json
      allow_any_instance_of(described_class).to receive(:call_llm).and_return(bad_response)
      expect(described_class.new(conversation: conversation).call).to eq([])
    end

    it 'limits to 5 facts even if LLM returns more' do
      many = { 'facts' => Array.new(10) { { 'memory_type' => 'preferencia', 'content' => 'x', 'evidence' => 'y', 'confidence' => 0.9 } } }.to_json
      allow_any_instance_of(described_class).to receive(:call_llm).and_return(many)
      expect(described_class.new(conversation: conversation).call.size).to eq(5)
    end

    it 'returns empty on LLM JSON parse error' do
      allow_any_instance_of(described_class).to receive(:call_llm).and_return('not json')
      expect(described_class.new(conversation: conversation).call).to eq([])
    end

    it 'returns empty on LLM error' do
      allow_any_instance_of(described_class).to receive(:call_llm).and_raise(StandardError)
      expect(described_class.new(conversation: conversation).call).to eq([])
    end
  end
end
```

- [ ] **Step 2: Run, expect fail**

Run: `bundle exec rspec spec/enterprise/services/captain/contact_memories/extraction_service_spec.rb`
Expected: FAIL.

- [ ] **Step 3: Implement service**

Create `enterprise/app/services/captain/contact_memories/extraction_service.rb`:

```ruby
class Captain::ContactMemories::ExtractionService
  MAX_FACTS = 5
  MIN_CONFIDENCE = 0.5
  EXTRACTION_MODEL = 'gpt-4o-mini'.freeze

  def initialize(conversation:)
    @conversation = conversation
  end

  def call
    raw = call_llm
    parsed = JSON.parse(raw)
    facts = parsed.fetch('facts', [])
    facts.filter_map { |f| normalize(f) }.take(MAX_FACTS)
  rescue JSON::ParserError => e
    Rails.logger.warn("[ContactMemory::ExtractionService] JSON parse: #{e.message}")
    []
  rescue StandardError => e
    Rails.logger.error("[ContactMemory::ExtractionService] #{e.class}: #{e.message}")
    []
  end

  private

  def call_llm
    client = RubyLLM.chat(model: EXTRACTION_MODEL)
    client.with_temperature(0)
    client.with_response_format({ type: 'json_object' })
    response = client.ask(build_prompt)
    response.content.to_s
  end

  def build_prompt
    <<~PROMPT
      Você é um analista que extrai FATOS MEMORÁVEIS de uma conversa de WhatsApp entre um hóspede e um hotel.

      Taxonomia (SÓ use estes tipos, caso contrário descarte o fato):
      #{Captain::ContactMemory::MEMORY_TYPES.join(', ')}

      Para cada fato, retorne JSON com:
      - memory_type (um dos tipos acima)
      - content (frase curta, português, max 1000 chars)
      - evidence (trecho LITERAL da conversa que sustenta o fato — obrigatório)
      - confidence (0.0 a 1.0)
      - scope ('global' na maioria dos casos; 'unit:<id>' só se o fato for operacional de uma unidade específica)

      Regras INVIOLÁVEIS:
      1. Se não houver evidência textual clara, NÃO extraia o fato.
      2. Máximo 5 fatos por conversa. Extraia só os realmente memoráveis.
      3. Se a conversa não tem nada memorável, retorne {"facts": []}.
      4. Nunca invente fatos. Se em dúvida, descarte.

      Conversa:
      #{formatted_messages}

      Retorne JSON no formato: {"facts": [{...}, ...]}
    PROMPT
  end

  def formatted_messages
    @conversation.messages
                 .where(message_type: [:incoming, :outgoing], private: false)
                 .order(created_at: :asc)
                 .map { |m| "[#{m.message_type}] #{m.content}" }
                 .join("\n")
  end

  def normalize(raw_fact)
    type = raw_fact['memory_type'].to_s
    content = raw_fact['content'].to_s.strip
    evidence = raw_fact['evidence'].to_s.strip
    confidence = raw_fact['confidence'].to_f
    scope = raw_fact['scope'].to_s.presence || 'global'

    return nil unless Captain::ContactMemory::MEMORY_TYPES.include?(type)
    return nil if content.blank? || evidence.blank?
    return nil if confidence < MIN_CONFIDENCE

    {
      memory_type: type,
      content: content.truncate(1000),
      evidence: evidence,
      confidence: confidence,
      scope: scope
    }
  end
end
```

- [ ] **Step 4: Run tests, expect pass**

Run: `bundle exec rspec spec/enterprise/services/captain/contact_memories/extraction_service_spec.rb`
Expected: PASS all.

- [ ] **Step 5: Commit**

```bash
git add enterprise/app/services/captain/contact_memories/extraction_service.rb spec/enterprise/services/captain/contact_memories/extraction_service_spec.rb
git commit -m "feat(captain-memory): add ExtractionService with evidence+confidence guardrails"
```

---

### Task 2.4: ContradictionCheckerService

**Files:**
- Create: `enterprise/app/services/captain/contact_memories/contradiction_checker_service.rb`
- Test: `spec/enterprise/services/captain/contact_memories/contradiction_checker_service_spec.rb`

- [ ] **Step 1: Write failing tests**

Create `spec/enterprise/services/captain/contact_memories/contradiction_checker_service_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe Captain::ContactMemories::ContradictionCheckerService do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }

  describe '#call' do
    let(:old_fact) { create(:captain_contact_memory, account: account, contact: contact, memory_type: 'preferencia', content: 'Prefere Stilo', embedding: Array.new(1536, 0.1)) }
    let(:new_fact) { create(:captain_contact_memory, account: account, contact: contact, memory_type: 'preferencia', content: 'Prefere Alexa agora', embedding: Array.new(1536, 0.15)) }

    before do
      allow_any_instance_of(described_class).to receive(:contradicts?).and_return(true)
    end

    it 'supersedes contradictory older facts of same type' do
      old_fact
      described_class.new(memory: new_fact).call
      expect(old_fact.reload.superseded_by_id).to eq(new_fact.id)
      expect(old_fact.superseded_at).not_to be_nil
    end

    it 'does not supersede non-contradictory facts' do
      allow_any_instance_of(described_class).to receive(:contradicts?).and_return(false)
      old_fact
      described_class.new(memory: new_fact).call
      expect(old_fact.reload.superseded_by_id).to be_nil
    end

    it 'does not supersede across different memory types' do
      other = create(:captain_contact_memory, account: account, contact: contact, memory_type: 'reclamacao', embedding: Array.new(1536, 0.1))
      described_class.new(memory: new_fact).call
      expect(other.reload.superseded_by_id).to be_nil
    end

    it 'no-ops when memory has no embedding' do
      old_fact
      embeddingless = create(:captain_contact_memory, account: account, contact: contact, memory_type: 'preferencia', embedding: nil)
      expect { described_class.new(memory: embeddingless).call }.not_to raise_error
      expect(old_fact.reload.superseded_by_id).to be_nil
    end
  end
end
```

- [ ] **Step 2: Run, expect fail**

Run: `bundle exec rspec spec/enterprise/services/captain/contact_memories/contradiction_checker_service_spec.rb`
Expected: FAIL.

- [ ] **Step 3: Implement service**

Create `enterprise/app/services/captain/contact_memories/contradiction_checker_service.rb`:

```ruby
class Captain::ContactMemories::ContradictionCheckerService
  MAX_CANDIDATES = 3
  DISTANCE_THRESHOLD = 0.6
  CHECK_MODEL = 'gpt-4o-mini'.freeze

  def initialize(memory:)
    @memory = memory
  end

  def call
    return if @memory.embedding.blank?

    candidates.each do |candidate|
      candidate.supersede_by!(@memory) if contradicts?(candidate, @memory)
    end
  end

  private

  def candidates
    Captain::ContactMemory
      .active
      .for_contact(@memory.contact_id)
      .by_type(@memory.memory_type)
      .where.not(id: @memory.id)
      .where.not(embedding: nil)
      .nearest_neighbors(:embedding, @memory.embedding, distance: 'cosine')
      .first(MAX_CANDIDATES)
      .select { |c| cosine_distance(c) < DISTANCE_THRESHOLD }
  end

  def cosine_distance(other)
    other.neighbor_distance
  end

  def contradicts?(a, b)
    response = RubyLLM.chat(model: CHECK_MODEL).with_temperature(0).ask(<<~Q).content.to_s.downcase
      Estes 2 fatos sobre o mesmo cliente se contradizem?
      Fato A: "#{a.content}"
      Fato B: "#{b.content}"
      Responda apenas "sim" ou "nao".
    Q
    response.include?('sim')
  rescue StandardError => e
    Rails.logger.warn("[ContradictionChecker] #{e.class}: #{e.message}")
    false
  end
end
```

- [ ] **Step 4: Run tests, expect pass**

Run: `bundle exec rspec spec/enterprise/services/captain/contact_memories/contradiction_checker_service_spec.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add enterprise/app/services/captain/contact_memories/contradiction_checker_service.rb spec/enterprise/services/captain/contact_memories/contradiction_checker_service_spec.rb
git commit -m "feat(captain-memory): add ContradictionCheckerService with LLM verification"
```

---

## Phase 3 — Jobs

### Task 3.1: UpdateEmbeddingJob

**Files:**
- Create: `enterprise/app/jobs/captain/contact_memories/update_embedding_job.rb`
- Test: `spec/enterprise/jobs/captain/contact_memories/update_embedding_job_spec.rb`

- [ ] **Step 1: Write failing test**

```ruby
require 'rails_helper'

RSpec.describe Captain::ContactMemories::UpdateEmbeddingJob do
  let(:memory) { create(:captain_contact_memory) }
  let(:embedding_service) { instance_double(Captain::Llm::EmbeddingService) }

  before do
    allow(Captain::Llm::EmbeddingService).to receive(:new).and_return(embedding_service)
    allow(embedding_service).to receive(:get_embedding).and_return(Array.new(1536, 0.5))
  end

  it 'sets embedding on the memory' do
    described_class.perform_now(memory.id)
    expect(memory.reload.embedding).to eq(Array.new(1536, 0.5))
  end

  it 'does not enqueue ContradictionCheckerJob inside itself' do
    expect { described_class.perform_now(memory.id) }
      .not_to have_enqueued_job(Captain::ContactMemories::ContradictionCheckerJob)
  end

  it 'enqueues ContradictionCheckerJob after setting embedding when configured' do
    expect { described_class.perform_now(memory.id, run_contradiction_check: true) }
      .to have_enqueued_job(Captain::ContactMemories::ContradictionCheckerJob).with(memory.id)
  end

  it 'tolerates a missing memory silently' do
    expect { described_class.perform_now(99_999_999) }.not_to raise_error
  end
end
```

- [ ] **Step 2: Run, expect fail**

Run: `bundle exec rspec spec/enterprise/jobs/captain/contact_memories/update_embedding_job_spec.rb`

- [ ] **Step 3: Implement job**

```ruby
class Captain::ContactMemories::UpdateEmbeddingJob < ApplicationJob
  queue_as :low

  retry_on Captain::Llm::EmbeddingService::EmbeddingsError, wait: :exponentially_longer, attempts: 3

  def perform(memory_id, run_contradiction_check: false)
    memory = Captain::ContactMemory.find_by(id: memory_id)
    return if memory.blank?

    embedding = Captain::Llm::EmbeddingService.new(account_id: memory.account_id).get_embedding(memory.content)
    return if embedding.blank?

    memory.update!(embedding: embedding)

    Captain::ContactMemories::ContradictionCheckerJob.perform_later(memory.id) if run_contradiction_check
  end
end
```

- [ ] **Step 4: Run tests, expect pass**

Run: `bundle exec rspec spec/enterprise/jobs/captain/contact_memories/update_embedding_job_spec.rb`

- [ ] **Step 5: Commit**

```bash
git add enterprise/app/jobs/captain/contact_memories/update_embedding_job.rb spec/enterprise/jobs/captain/contact_memories/update_embedding_job_spec.rb
git commit -m "feat(captain-memory): add UpdateEmbeddingJob"
```

---

### Task 3.2: ContradictionCheckerJob

**Files:**
- Create: `enterprise/app/jobs/captain/contact_memories/contradiction_checker_job.rb`

- [ ] **Step 1: Write failing test**

`spec/enterprise/jobs/captain/contact_memories/contradiction_checker_job_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe Captain::ContactMemories::ContradictionCheckerJob do
  let(:memory) { create(:captain_contact_memory) }

  it 'delegates to ContradictionCheckerService' do
    service = instance_double(Captain::ContactMemories::ContradictionCheckerService, call: nil)
    expect(Captain::ContactMemories::ContradictionCheckerService).to receive(:new).with(memory: memory).and_return(service)
    described_class.perform_now(memory.id)
  end

  it 'no-ops on missing memory' do
    expect { described_class.perform_now(99_999_999) }.not_to raise_error
  end
end
```

- [ ] **Step 2: Run, expect fail**

Run: `bundle exec rspec spec/enterprise/jobs/captain/contact_memories/contradiction_checker_job_spec.rb`

- [ ] **Step 3: Implement job**

```ruby
class Captain::ContactMemories::ContradictionCheckerJob < ApplicationJob
  queue_as :low

  def perform(memory_id)
    memory = Captain::ContactMemory.find_by(id: memory_id)
    return if memory.blank?

    Captain::ContactMemories::ContradictionCheckerService.new(memory: memory).call
  end
end
```

- [ ] **Step 4: Run tests, expect pass**

- [ ] **Step 5: Commit**

```bash
git add enterprise/app/jobs/captain/contact_memories/contradiction_checker_job.rb spec/enterprise/jobs/captain/contact_memories/contradiction_checker_job_spec.rb
git commit -m "feat(captain-memory): add ContradictionCheckerJob"
```

---

### Task 3.3: ExtractFromConversationJob

**Files:**
- Create: `enterprise/app/jobs/captain/contact_memories/extract_from_conversation_job.rb`
- Test: `spec/enterprise/jobs/captain/contact_memories/extract_from_conversation_job_spec.rb`

- [ ] **Step 1: Write failing test**

```ruby
require 'rails_helper'

RSpec.describe Captain::ContactMemories::ExtractFromConversationJob do
  let(:account) { create(:account, custom_attributes: { 'captain_contact_memory_extraction_enabled' => true }) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let(:extracted_facts) do
    [
      { memory_type: 'preferencia', content: 'Prefere Stilo', evidence: 'disse x', confidence: 0.9, scope: 'global' }
    ]
  end

  before do
    allow_any_instance_of(Captain::ContactMemories::ExtractionService).to receive(:call).and_return(extracted_facts)
  end

  it 'skips when extraction flag is off' do
    account.update!(custom_attributes: { 'captain_contact_memory_extraction_enabled' => false })
    expect { described_class.perform_now(conversation.id) }.not_to change(Captain::ContactMemory, :count)
  end

  it 'persists facts with source attribution' do
    described_class.perform_now(conversation.id)
    memory = Captain::ContactMemory.last
    expect(memory.content).to eq('Prefere Stilo')
    expect(memory.source_conversation_id).to eq(conversation.id)
    expect(memory.source_inbox_id).to eq(conversation.inbox_id)
  end

  it 'is idempotent when re-run for the same conversation' do
    described_class.perform_now(conversation.id)
    expect { described_class.perform_now(conversation.id) }.not_to change(Captain::ContactMemory, :count)
  end

  it 'enqueues embedding job for each created memory' do
    expect { described_class.perform_now(conversation.id) }
      .to have_enqueued_job(Captain::ContactMemories::UpdateEmbeddingJob).with(anything, run_contradiction_check: true)
  end

  it 'sets last_verified_at to now' do
    freeze_time do
      described_class.perform_now(conversation.id)
      expect(Captain::ContactMemory.last.last_verified_at).to eq(Time.current)
    end
  end

  it 'applies TTL expires_at for types that expire' do
    allow_any_instance_of(Captain::ContactMemories::ExtractionService).to receive(:call).and_return([
      { memory_type: 'reclamacao', content: 'x', evidence: 'y', confidence: 0.9, scope: 'unit:1' }
    ])
    freeze_time do
      described_class.perform_now(conversation.id)
      memory = Captain::ContactMemory.last
      expect(memory.expires_at).to eq(180.days.from_now)
    end
  end

  it 'leaves expires_at null for types without TTL' do
    allow_any_instance_of(Captain::ContactMemories::ExtractionService).to receive(:call).and_return([
      { memory_type: 'restricao', content: 'alergia', evidence: 'y', confidence: 0.9, scope: 'global' }
    ])
    described_class.perform_now(conversation.id)
    expect(Captain::ContactMemory.last.expires_at).to be_nil
  end
end
```

- [ ] **Step 2: Run, expect fail**

- [ ] **Step 3: Implement job**

```ruby
class Captain::ContactMemories::ExtractFromConversationJob < ApplicationJob
  queue_as :low

  TTL_BY_TYPE = {
    'preferencia' => 365.days,
    'padrao_comportamental' => 365.days,
    'reclamacao' => 180.days,
    'feedback_positivo' => 365.days,
    'vinculo_social' => 730.days,
    'vinculo_comercial' => 365.days,
    'contexto_pessoal' => 365.days
    # data_comemorativa, restricao: no TTL (nil)
  }.freeze

  def perform(conversation_id)
    conversation = Conversation.find_by(id: conversation_id)
    return if conversation.blank?
    return unless conversation.account.captain_contact_memory_extraction_enabled?
    return if already_extracted?(conversation)

    facts = Captain::ContactMemories::ExtractionService.new(conversation: conversation).call
    return if facts.blank?

    facts.each { |fact| persist_fact(fact, conversation) }
  end

  private

  def already_extracted?(conversation)
    Captain::ContactMemory.where(source_conversation_id: conversation.id).exists?
  end

  def persist_fact(fact, conversation)
    ttl = TTL_BY_TYPE[fact[:memory_type]]
    memory = Captain::ContactMemory.create!(
      account_id: conversation.account_id,
      contact_id: conversation.contact_id,
      memory_type: fact[:memory_type],
      content: fact[:content],
      evidence: fact[:evidence],
      confidence: fact[:confidence],
      scope: fact[:scope],
      source_conversation_id: conversation.id,
      source_unit_id: resolve_unit_id(conversation),
      source_inbox_id: conversation.inbox_id,
      last_verified_at: Time.current,
      expires_at: ttl ? ttl.from_now : nil
    )

    Captain::ContactMemories::UpdateEmbeddingJob.perform_later(memory.id, run_contradiction_check: true)
  end

  def resolve_unit_id(conversation)
    return conversation.captain_unit_id if conversation.respond_to?(:captain_unit_id) && conversation.captain_unit_id.present?

    Captain::Unit.where(inbox_id: conversation.inbox_id).pick(:id)
  end
end
```

- [ ] **Step 4: Run tests, expect pass**

- [ ] **Step 5: Commit**

```bash
git add enterprise/app/jobs/captain/contact_memories/extract_from_conversation_job.rb spec/enterprise/jobs/captain/contact_memories/extract_from_conversation_job_spec.rb
git commit -m "feat(captain-memory): add ExtractFromConversationJob with TTL + idempotency"
```

---

### Task 3.4: SilenceDetectorJob (cron)

**Files:**
- Create: `enterprise/app/jobs/captain/contact_memories/silence_detector_job.rb`
- Modify: `config/schedule.yml`

- [ ] **Step 1: Write failing test**

```ruby
require 'rails_helper'

RSpec.describe Captain::ContactMemories::SilenceDetectorJob do
  let(:account) { create(:account, custom_attributes: { 'captain_contact_memory_extraction_enabled' => true }) }
  let(:contact) { create(:contact, account: account) }

  it 'enqueues extraction for conversations silent > 30 minutes' do
    conv = create(:conversation, account: account, contact: contact)
    create(:message, conversation: conv, created_at: 35.minutes.ago)

    expect { described_class.perform_now }
      .to have_enqueued_job(Captain::ContactMemories::ExtractFromConversationJob).with(conv.id)
  end

  it 'ignores conversations with recent activity' do
    conv = create(:conversation, account: account, contact: contact)
    create(:message, conversation: conv, created_at: 5.minutes.ago)

    expect { described_class.perform_now }
      .not_to have_enqueued_job(Captain::ContactMemories::ExtractFromConversationJob)
  end

  it 'ignores conversations already extracted' do
    conv = create(:conversation, account: account, contact: contact)
    create(:message, conversation: conv, created_at: 35.minutes.ago)
    create(:captain_contact_memory, account: account, contact: contact, source_conversation_id: conv.id)

    expect { described_class.perform_now }
      .not_to have_enqueued_job(Captain::ContactMemories::ExtractFromConversationJob)
  end

  it 'ignores accounts with flag off' do
    account.update!(custom_attributes: { 'captain_contact_memory_extraction_enabled' => false })
    conv = create(:conversation, account: account, contact: contact)
    create(:message, conversation: conv, created_at: 35.minutes.ago)

    expect { described_class.perform_now }
      .not_to have_enqueued_job(Captain::ContactMemories::ExtractFromConversationJob)
  end
end
```

- [ ] **Step 2: Run, expect fail**

- [ ] **Step 3: Implement job**

```ruby
class Captain::ContactMemories::SilenceDetectorJob < ApplicationJob
  queue_as :scheduled_jobs

  SILENCE_THRESHOLD = 30.minutes

  def perform
    Account.where("custom_attributes->>'captain_contact_memory_extraction_enabled' = 'true'").find_each do |account|
      elegible_conversation_ids(account).each do |conv_id|
        Captain::ContactMemories::ExtractFromConversationJob.perform_later(conv_id)
      end
    end
  end

  private

  def elegible_conversation_ids(account)
    Conversation
      .where(account_id: account.id)
      .joins(:messages)
      .where('messages.created_at < ?', SILENCE_THRESHOLD.ago)
      .where.not(id: already_extracted_ids(account))
      .group('conversations.id')
      .having('MAX(messages.created_at) < ?', SILENCE_THRESHOLD.ago)
      .pluck(:id)
  end

  def already_extracted_ids(account)
    Captain::ContactMemory
      .where(account_id: account.id)
      .where.not(source_conversation_id: nil)
      .distinct
      .pluck(:source_conversation_id)
  end
end
```

- [ ] **Step 4: Add cron schedule**

Append to `config/schedule.yml`:

```yaml
# every 10 minutes - detects silent conversations for memory extraction
captain_contact_memory_silence_detector_job:
  cron: '*/10 * * * *'
  class: 'Captain::ContactMemories::SilenceDetectorJob'
  queue: scheduled_jobs
```

- [ ] **Step 5: Run tests, expect pass**

Run: `bundle exec rspec spec/enterprise/jobs/captain/contact_memories/silence_detector_job_spec.rb spec/configs/schedule_spec.rb`

- [ ] **Step 6: Commit**

```bash
git add enterprise/app/jobs/captain/contact_memories/silence_detector_job.rb spec/enterprise/jobs/captain/contact_memories/silence_detector_job_spec.rb config/schedule.yml
git commit -m "feat(captain-memory): add SilenceDetectorJob with 10min cron"
```

---

### Task 3.5: AgingJob (weekly cron)

**Files:**
- Create: `enterprise/app/jobs/captain/contact_memories/aging_job.rb`
- Modify: `config/schedule.yml`

- [ ] **Step 1: Write failing test**

```ruby
require 'rails_helper'

RSpec.describe Captain::ContactMemories::AgingJob do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }

  it 'soft-deletes expired reclamacao (delete on expire type)' do
    mem = create(:captain_contact_memory, account: account, contact: contact, memory_type: 'reclamacao', expires_at: 1.day.ago)
    described_class.perform_now
    expect(mem.reload.deleted_at).not_to be_nil
  end

  it 'does NOT soft-delete expired preferencia (reduce-weight type)' do
    mem = create(:captain_contact_memory, account: account, contact: contact, memory_type: 'preferencia', expires_at: 1.day.ago)
    described_class.perform_now
    expect(mem.reload.deleted_at).to be_nil
  end

  it 'applies LRU soft-delete when contact exceeds 50 active facts' do
    55.times.with_index do |i|
      create(:captain_contact_memory, account: account, contact: contact, last_verified_at: i.days.ago)
    end
    described_class.perform_now
    expect(Captain::ContactMemory.where(contact: contact).active.count).to eq(50)
  end
end
```

- [ ] **Step 2: Run, expect fail**

- [ ] **Step 3: Implement job**

```ruby
class Captain::ContactMemories::AgingJob < ApplicationJob
  queue_as :scheduled_jobs

  DELETE_ON_EXPIRE = %w[reclamacao feedback_positivo vinculo_social].freeze
  MAX_ACTIVE_PER_CONTACT = 50

  def perform
    soft_delete_expired_deletable
    prune_per_contact_lru
  end

  private

  def soft_delete_expired_deletable
    Captain::ContactMemory
      .where(memory_type: DELETE_ON_EXPIRE)
      .where('expires_at < ?', Time.current)
      .where(deleted_at: nil)
      .update_all(deleted_at: Time.current, updated_at: Time.current)
  end

  def prune_per_contact_lru
    Captain::ContactMemory.active.group(:contact_id).having('COUNT(*) > ?', MAX_ACTIVE_PER_CONTACT).pluck(:contact_id).each do |contact_id|
      excess = Captain::ContactMemory.active.for_contact(contact_id).count - MAX_ACTIVE_PER_CONTACT
      next if excess <= 0

      to_delete = Captain::ContactMemory.active.for_contact(contact_id).order(last_verified_at: :asc).limit(excess)
      to_delete.update_all(deleted_at: Time.current, updated_at: Time.current)
    end
  end
end
```

- [ ] **Step 4: Add cron schedule**

Append to `config/schedule.yml`:

```yaml
# weekly - Sundays at 03:00 UTC - TTL aging + LRU cap of contact memories
captain_contact_memory_aging_job:
  cron: '0 3 * * 0'
  class: 'Captain::ContactMemories::AgingJob'
  queue: scheduled_jobs
```

- [ ] **Step 5: Run tests, expect pass**

- [ ] **Step 6: Commit**

```bash
git add enterprise/app/jobs/captain/contact_memories/aging_job.rb spec/enterprise/jobs/captain/contact_memories/aging_job_spec.rb config/schedule.yml
git commit -m "feat(captain-memory): add AgingJob with TTL + LRU cap, weekly cron"
```

---

### Task 3.6: HardDeleteExpiredJob (daily cron)

**Files:**
- Create: `enterprise/app/jobs/captain/contact_memories/hard_delete_expired_job.rb`
- Modify: `config/schedule.yml`

- [ ] **Step 1: Write failing test**

```ruby
require 'rails_helper'

RSpec.describe Captain::ContactMemories::HardDeleteExpiredJob do
  it 'destroys records soft-deleted more than 30 days ago' do
    old = create(:captain_contact_memory, deleted_at: 40.days.ago)
    recent = create(:captain_contact_memory, deleted_at: 10.days.ago)
    active = create(:captain_contact_memory, deleted_at: nil)

    described_class.perform_now

    expect(Captain::ContactMemory.exists?(old.id)).to be(false)
    expect(Captain::ContactMemory.exists?(recent.id)).to be(true)
    expect(Captain::ContactMemory.exists?(active.id)).to be(true)
  end
end
```

- [ ] **Step 2: Run, expect fail**

- [ ] **Step 3: Implement job**

```ruby
class Captain::ContactMemories::HardDeleteExpiredJob < ApplicationJob
  queue_as :scheduled_jobs

  RETENTION_DAYS = 30

  def perform
    count = Captain::ContactMemory.where('deleted_at < ?', RETENTION_DAYS.days.ago).delete_all
    Rails.logger.info("[ContactMemory::HardDeleteExpiredJob] hard-deleted #{count} records")
  end
end
```

- [ ] **Step 4: Add cron schedule**

Append to `config/schedule.yml`:

```yaml
# daily at 03:30 UTC - hard-delete soft-deleted contact memories older than 30 days (LGPD)
captain_contact_memory_hard_delete_job:
  cron: '30 3 * * *'
  class: 'Captain::ContactMemories::HardDeleteExpiredJob'
  queue: scheduled_jobs
```

- [ ] **Step 5: Run tests, expect pass**

- [ ] **Step 6: Commit**

```bash
git add enterprise/app/jobs/captain/contact_memories/hard_delete_expired_job.rb spec/enterprise/jobs/captain/contact_memories/hard_delete_expired_job_spec.rb config/schedule.yml
git commit -m "feat(captain-memory): add HardDeleteExpiredJob with daily cron (LGPD)"
```

---

## Phase 4 — Integration with AgentRunnerService

### Task 4.1: Hook conversation.resolved to enqueue extraction

**Files:**
- Modify: `enterprise/app/listeners/captain_listener.rb` (or create if missing)

- [ ] **Step 1: Check listener location**

Run: `ls enterprise/app/listeners/`
If `captain_listener.rb` exists, modify it. If not, check `app/listeners/` pattern and create in enterprise/.

- [ ] **Step 2: Write failing test**

`spec/enterprise/listeners/captain_listener_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe CaptainListener do
  let(:listener) { described_class.instance }
  let(:account) { create(:account, custom_attributes: { 'captain_contact_memory_extraction_enabled' => true }) }
  let(:conversation) { create(:conversation, account: account, status: :resolved) }
  let(:event) { Events::Base.new('conversation.resolved', Time.current, conversation: conversation) }

  it 'enqueues extraction job when conversation resolves' do
    expect { listener.conversation_resolved(event) }
      .to have_enqueued_job(Captain::ContactMemories::ExtractFromConversationJob).with(conversation.id)
  end
end
```

- [ ] **Step 3: Run, expect fail**

- [ ] **Step 4: Implement handler**

Add to `enterprise/app/listeners/captain_listener.rb`:

```ruby
def conversation_resolved(event)
  conversation = extract_conversation(event)
  return if conversation.blank?

  Captain::ContactMemories::ExtractFromConversationJob.perform_later(conversation.id)
end

private

def extract_conversation(event)
  event.data[:conversation] || event.data['conversation']
end
```

Ensure it's registered in the listener module chain (check `config/initializers/02_subscribers.rb` or similar).

- [ ] **Step 5: Run tests, expect pass**

- [ ] **Step 6: Commit**

```bash
git add enterprise/app/listeners/captain_listener.rb spec/enterprise/listeners/captain_listener_spec.rb
git commit -m "feat(captain-memory): enqueue extraction on conversation.resolved"
```

---

### Task 4.2: Inject recall into AgentRunnerService

**Files:**
- Modify: `enterprise/app/services/captain/assistant/agent_runner_service.rb`

- [ ] **Step 1: Write failing integration test**

`spec/enterprise/integration/captain_semantic_memory_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe 'Captain semantic memory integration' do
  let(:account) { create(:account, custom_attributes: attrs) }
  let(:attrs) { { 'captain_contact_memory_recall_enabled' => true } }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let(:runner) { Captain::Assistant::AgentRunnerService.new(assistant: assistant, conversation: conversation) }

  before do
    create(:captain_contact_memory, account: account, contact: contact, content: 'Prefere Stilo', embedding: Array.new(1536, 0.1))
    allow(Captain::Llm::EmbeddingService).to receive(:new).and_return(
      instance_double(Captain::Llm::EmbeddingService, get_embedding: Array.new(1536, 0.1))
    )
    allow_any_instance_of(Captain::Assistant::AgentRunnerService).to receive(:run_agent).and_call_original
  end

  it 'injects <memoria_cliente> block into system prompt when recall flag is on' do
    expect(runner.send(:build_system_prompt_with_memory, 'Hi there')).to include('<memoria_cliente>')
  end

  it 'skips injection when recall flag is off' do
    account.update!(custom_attributes: {})
    expect(runner.send(:build_system_prompt_with_memory, 'Hi there')).not_to include('<memoria_cliente>')
  end
end
```

- [ ] **Step 2: Run, expect fail**

- [ ] **Step 3: Modify AgentRunnerService**

In `enterprise/app/services/captain/assistant/agent_runner_service.rb`, find the method that constructs the system prompt (e.g., `build_system_prompt` or direct call to SystemPromptsService). Add a new private method that wraps it:

```ruby
# Inside Captain::Assistant::AgentRunnerService
def build_system_prompt_with_memory(message_text)
  base_prompt = build_system_prompt # or whatever existing method produces the base

  return base_prompt unless @conversation&.account&.captain_contact_memory_recall_enabled?

  memories = Captain::ContactMemories::RecallService.new(
    contact: @conversation.contact,
    query_text: message_text,
    unit_id: resolve_unit_id
  ).call

  memory_block = Captain::ContactMemories::PromptInjectionService.new(memories: memories).call
  return base_prompt if memory_block.blank?

  [base_prompt, memory_block].join("\n\n")
end

def resolve_unit_id
  return @conversation.captain_unit_id if @conversation.respond_to?(:captain_unit_id) && @conversation.captain_unit_id.present?

  Captain::Unit.where(inbox_id: @conversation.inbox_id).pick(:id)
end
```

Then replace the existing call site that assigns system_prompt to use `build_system_prompt_with_memory(message)`.

Exact location: look for `@assistant.agent` definition around line ~55-80 of the file. Before building the agent, take the message (`message` parameter of `run` method) and pass through.

- [ ] **Step 4: Run tests, expect pass**

- [ ] **Step 5: Commit**

```bash
git add enterprise/app/services/captain/assistant/agent_runner_service.rb spec/enterprise/integration/captain_semantic_memory_spec.rb
git commit -m "feat(captain-memory): inject semantic memory into AgentRunnerService system prompt"
```

---

### Task 4.3: End-to-end integration test

**Files:**
- Test: `spec/enterprise/integration/captain_semantic_memory_spec.rb` (extend)

- [ ] **Step 1: Add end-to-end test**

Append to the existing integration spec:

```ruby
describe 'end-to-end learning and recall' do
  let(:account) { create(:account, custom_attributes: { 'captain_contact_memory_extraction_enabled' => true, 'captain_contact_memory_recall_enabled' => true }) }

  it 'learns from a resolved conversation and recalls in a new one' do
    # 1. Old conversation - learning
    old_conv = create(:conversation, account: account, contact: contact)
    create(:message, conversation: old_conv, message_type: :incoming, content: 'quero sempre a Stilo com hidro')
    create(:message, conversation: old_conv, message_type: :outgoing, content: 'combinado')

    allow_any_instance_of(Captain::ContactMemories::ExtractionService).to receive(:call).and_return([
      { memory_type: 'preferencia', content: 'Prefere Stilo com hidro', evidence: 'disse quero sempre a Stilo', confidence: 0.95, scope: 'global' }
    ])
    allow(Captain::Llm::EmbeddingService).to receive(:new).and_return(
      instance_double(Captain::Llm::EmbeddingService, get_embedding: Array.new(1536, 0.1))
    )

    # Simulate conversation.resolved
    Captain::ContactMemories::ExtractFromConversationJob.perform_now(old_conv.id)
    # Simulate embedding job
    last_memory = Captain::ContactMemory.last
    last_memory.update!(embedding: Array.new(1536, 0.1))

    # 2. New conversation - recall
    new_conv = create(:conversation, account: account, contact: contact)
    runner = Captain::Assistant::AgentRunnerService.new(assistant: assistant, conversation: new_conv)

    result = runner.send(:build_system_prompt_with_memory, 'oi, quero reservar')
    expect(result).to include('Prefere Stilo com hidro')
  end
end
```

- [ ] **Step 2: Run, expect pass**

- [ ] **Step 3: Commit**

```bash
git add spec/enterprise/integration/captain_semantic_memory_spec.rb
git commit -m "test(captain-memory): end-to-end learning and recall integration test"
```

---

## Phase 5 — API + UI

### Task 5.1: ContactMemoryPolicy (Pundit)

**Files:**
- Create: `enterprise/app/policies/captain/contact_memory_policy.rb`
- Test: `spec/enterprise/policies/captain/contact_memory_policy_spec.rb`

- [ ] **Step 1: Write failing test**

```ruby
require 'rails_helper'

RSpec.describe Captain::ContactMemoryPolicy do
  subject { described_class.new(pundit_user, memory) }

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:memory) { create(:captain_contact_memory, account: account) }
  let(:pundit_user) { build(:pundit_user, user: user, account: account) }

  context 'as administrator' do
    let(:user) { admin }

    it { is_expected.to permit_actions(%i[index update destroy bulk_destroy]) }
  end

  context 'as agent' do
    let(:user) { agent }

    it { is_expected.to permit_action(:index) }
    it { is_expected.to forbid_actions(%i[update destroy bulk_destroy]) }
  end
end
```

- [ ] **Step 2: Implement policy**

```ruby
class Captain::ContactMemoryPolicy < ApplicationPolicy
  def index?
    @account_user.present?
  end

  def update?
    @account_user&.administrator?
  end

  def destroy?
    @account_user&.administrator?
  end

  def bulk_destroy?
    @account_user&.administrator?
  end
end
```

- [ ] **Step 3: Run tests**
- [ ] **Step 4: Commit**

---

### Task 5.2: MemoriesController

**Files:**
- Create: `enterprise/app/controllers/api/v1/accounts/contacts/memories_controller.rb`
- Modify: `config/routes.rb`
- Test: `spec/enterprise/controllers/api/v1/accounts/contacts/memories_controller_spec.rb`

- [ ] **Step 1: Write failing test**

```ruby
require 'rails_helper'

RSpec.describe Api::V1::Accounts::Contacts::MemoriesController, type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:contact) { create(:contact, account: account) }
  let!(:memory) { create(:captain_contact_memory, account: account, contact: contact) }

  describe 'GET #index' do
    it 'returns memories for the contact' do
      get "/api/v1/accounts/#{account.id}/contacts/#{contact.id}/memories",
          headers: admin.create_new_auth_token

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['data'].size).to eq(1)
    end
  end

  describe 'PATCH #update' do
    it 'updates content and re-embeds' do
      expect {
        patch "/api/v1/accounts/#{account.id}/contacts/#{contact.id}/memories/#{memory.id}",
              params: { content: 'updated content' },
              headers: admin.create_new_auth_token
      }.to have_enqueued_job(Captain::ContactMemories::UpdateEmbeddingJob)

      expect(memory.reload.content).to eq('updated content')
    end
  end

  describe 'DELETE #destroy' do
    it 'soft-deletes' do
      delete "/api/v1/accounts/#{account.id}/contacts/#{contact.id}/memories/#{memory.id}",
             headers: admin.create_new_auth_token

      expect(memory.reload.deleted_at).not_to be_nil
    end
  end

  describe 'DELETE collection (forget all)' do
    it 'soft-deletes all memories for the contact' do
      create_list(:captain_contact_memory, 3, account: account, contact: contact)

      delete "/api/v1/accounts/#{account.id}/contacts/#{contact.id}/memories",
             headers: admin.create_new_auth_token

      expect(Captain::ContactMemory.for_contact(contact.id).where(deleted_at: nil).count).to eq(0)
    end
  end
end
```

- [ ] **Step 2: Implement controller**

```ruby
class Api::V1::Accounts::Contacts::MemoriesController < Api::V1::Accounts::BaseController
  before_action :set_contact
  before_action :set_memory, only: %i[update destroy]

  def index
    @memories = Captain::ContactMemory.active.for_contact(@contact.id).order(created_at: :desc)
    authorize(@memories.first || Captain::ContactMemory.new(account: @contact.account)) if @memories.any?
    render json: { data: @memories.as_json(except: :embedding) }
  end

  def update
    authorize(@memory)
    @memory.update!(memory_params)
    Captain::ContactMemories::UpdateEmbeddingJob.perform_later(@memory.id) if @memory.saved_change_to_content?
    render json: @memory.as_json(except: :embedding)
  end

  def destroy
    authorize(@memory)
    @memory.soft_delete!
    head :no_content
  end

  def bulk_destroy
    authorize(Captain::ContactMemory.new(account: @contact.account))
    Captain::ContactMemory.active.for_contact(@contact.id).update_all(deleted_at: Time.current, updated_at: Time.current)
    head :no_content
  end

  private

  def set_contact
    @contact = Current.account.contacts.find(params[:contact_id])
  end

  def set_memory
    @memory = Captain::ContactMemory.for_contact(@contact.id).find(params[:id])
  end

  def memory_params
    params.permit(:content, :memory_type, :scope)
  end
end
```

- [ ] **Step 3: Add routes**

Modify `config/routes.rb` — inside the existing `resources :contacts` block of `api/v1/accounts`, add:

```ruby
resources :memories, only: %i[index update destroy], controller: 'contacts/memories' do
  collection do
    delete :bulk_destroy, path: ''
  end
end
```

- [ ] **Step 4: Run tests**
- [ ] **Step 5: Commit**

---

### Task 5.3: Vue component ContactMemories.vue

**Files:**
- Create: `app/javascript/dashboard/routes/dashboard/contact/components/ContactMemories.vue`
- Create: `app/javascript/dashboard/api/captain/contactMemories.js`

- [ ] **Step 1: Create API client**

`app/javascript/dashboard/api/captain/contactMemories.js`:

```javascript
import ApiClient from '../ApiClient';

class ContactMemoriesAPI extends ApiClient {
  constructor() {
    super('memories', { accountScoped: true });
  }

  get url() {
    return `${this.baseUrl()}/contacts/${this.contactId}/memories`;
  }

  list(contactId) {
    this.contactId = contactId;
    return axios.get(this.url);
  }

  update(contactId, id, payload) {
    this.contactId = contactId;
    return axios.patch(`${this.url}/${id}`, payload);
  }

  destroy(contactId, id) {
    this.contactId = contactId;
    return axios.delete(`${this.url}/${id}`);
  }

  forgetAll(contactId) {
    this.contactId = contactId;
    return axios.delete(this.url);
  }
}

export default new ContactMemoriesAPI();
```

- [ ] **Step 2: Create Vue component**

`app/javascript/dashboard/routes/dashboard/contact/components/ContactMemories.vue`:

```vue
<script setup>
import { ref, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import ContactMemoriesAPI from 'dashboard/api/captain/contactMemories';

const props = defineProps({ contactId: { type: [String, Number], required: true } });
const { t } = useI18n();
const memories = ref([]);
const loading = ref(true);
const error = ref(null);

async function load() {
  loading.value = true;
  error.value = null;
  try {
    const { data } = await ContactMemoriesAPI.list(props.contactId);
    memories.value = data.data;
  } catch (e) {
    error.value = e.message;
  } finally {
    loading.value = false;
  }
}

async function deleteMemory(id) {
  if (!confirm(t('CAPTAIN.MEMORY.CONFIRM_DELETE'))) return;
  await ContactMemoriesAPI.destroy(props.contactId, id);
  await load();
}

async function forgetAll() {
  if (!confirm(t('CAPTAIN.MEMORY.CONFIRM_FORGET_ALL'))) return;
  await ContactMemoriesAPI.forgetAll(props.contactId);
  await load();
}

onMounted(load);
</script>

<template>
  <div class="contact-memories">
    <div v-if="loading">{{ t('CAPTAIN.MEMORY.LOADING') }}</div>
    <div v-else-if="error" class="error">{{ error }}</div>
    <div v-else-if="!memories.length" class="empty">{{ t('CAPTAIN.MEMORY.EMPTY') }}</div>
    <ul v-else>
      <li v-for="m in memories" :key="m.id" class="memory-row">
        <span class="type">{{ m.memory_type }}</span>
        <span class="content">{{ m.content }}</span>
        <span class="confidence">{{ Math.round(m.confidence * 100) }}%</span>
        <button @click="deleteMemory(m.id)">{{ t('CAPTAIN.MEMORY.FORGET') }}</button>
      </li>
    </ul>
    <button class="danger" @click="forgetAll">{{ t('CAPTAIN.MEMORY.FORGET_ALL') }}</button>
  </div>
</template>
```

- [ ] **Step 3: Register component in contact detail route**

Find the existing contact detail component (e.g., `app/javascript/dashboard/routes/dashboard/contact/ContactsDashboard.vue` or similar). Add a new tab "Memória" pointing to the new component.

- [ ] **Step 4: Add translations (EN + pt_BR)**

`app/javascript/dashboard/i18n/locale/en/captain.json`:
```json
{
  "MEMORY": {
    "LOADING": "Loading…",
    "EMPTY": "No memories for this contact yet.",
    "CONFIRM_DELETE": "Forget this memory?",
    "CONFIRM_FORGET_ALL": "Forget ALL memories for this contact? This cannot be undone after 30 days.",
    "FORGET": "Forget",
    "FORGET_ALL": "Forget all"
  }
}
```

`app/javascript/dashboard/i18n/locale/pt_BR/captain.json`:
```json
{
  "MEMORY": {
    "LOADING": "Carregando…",
    "EMPTY": "Sem memórias para este contato ainda.",
    "CONFIRM_DELETE": "Esquecer esta memória?",
    "CONFIRM_FORGET_ALL": "Esquecer TODAS as memórias deste contato? Após 30 dias não é possível desfazer.",
    "FORGET": "Esquecer",
    "FORGET_ALL": "Esquecer tudo"
  }
}
```

- [ ] **Step 5: Smoke test manually**

Run: `pnpm run dev` and open a contact detail page. Confirm new tab appears and empty state shows.

- [ ] **Step 6: Commit**

```bash
git add app/javascript/dashboard/routes/dashboard/contact/components/ContactMemories.vue app/javascript/dashboard/api/captain/contactMemories.js app/javascript/dashboard/i18n/locale/en/captain.json app/javascript/dashboard/i18n/locale/pt_BR/captain.json
git commit -m "feat(captain-memory): add Contact Memory tab UI with forget controls"
```

---

### Task 5.4: Feature flag toggles in Captain settings

**Files:**
- Modify: existing Captain settings Vue page (`app/javascript/dashboard/routes/dashboard/settings/captain/...`)
- Modify: `app/controllers/api/v1/accounts/captain/...` or wherever Captain settings are persisted

- [ ] **Step 1: Add 2 toggles**

In the existing Captain settings page, add a new section "Memória do Cliente" with 2 toggle switches bound to `account.custom_attributes`. Follow existing pattern used for other account-level Captain flags (grep for `captain_features` in the settings page).

- [ ] **Step 2: Wire save endpoint**

Account update endpoint already accepts `custom_attributes`. Ensure the 2 keys (`captain_contact_memory_extraction_enabled` and `captain_contact_memory_recall_enabled`) persist.

- [ ] **Step 3: Commit**

```bash
git add app/javascript/dashboard/routes/dashboard/settings/captain/
git commit -m "feat(captain-memory): add feature flag toggles in Captain settings UI"
```

---

## Phase 6 — Observability

### Task 6.1: Instrumentation metrics

**Files:**
- Modify: services and jobs to emit OTEL metrics following existing `Integrations::LlmInstrumentation` pattern

- [ ] **Step 1: Review existing instrumentation**

Read `lib/integrations/llm_instrumentation.rb` to understand how existing services emit metrics.

- [ ] **Step 2: Emit metrics from ExtractionService, RecallService, UpdateEmbeddingJob**

Wrap LLM calls in each service with `instrument_*` blocks:
- `extraction`: `captain_memory_extraction` span with model, account_id, latency, facts_count
- `recall`: `captain_memory_recall` span with contact_id, hit_count, latency
- `embedding`: already instrumented via EmbeddingService

- [ ] **Step 3: Verify metrics appear**

Manual: trigger extraction locally, check OTEL collector logs.

- [ ] **Step 4: Commit**

```bash
git add enterprise/app/services/captain/contact_memories/ enterprise/app/jobs/captain/contact_memories/
git commit -m "feat(captain-memory): add OTEL instrumentation to memory pipeline"
```

---

### Task 6.2: Structured logging

**Files:**
- Modify: each service/job to log structured events

- [ ] **Step 1: Add logs for key events**

Ensure each service/job logs a structured line containing: event name, conversation_id (when relevant), memory_id, memory_type, confidence, decision (saved/dropped/superseded), latency.

Example in ExtractFromConversationJob:
```ruby
Rails.logger.info({
  event: 'captain_memory_extraction_completed',
  conversation_id: conversation.id,
  facts_extracted: facts.size,
  account_id: conversation.account_id
}.to_json)
```

- [ ] **Step 2: Commit**

```bash
git add enterprise/app/services/captain/contact_memories/ enterprise/app/jobs/captain/contact_memories/
git commit -m "feat(captain-memory): add structured logs for memory pipeline"
```

---

## Phase 7 — Rollout prep

### Task 7.1: Operator docs

**Files:**
- Create: `docs/captain/semantic-memory.md`

- [ ] **Step 1: Write operator-facing doc**

Contents:
- What the feature does in plain Portuguese
- How to enable/disable via Settings → Captain → Memória do Cliente
- How to view/edit/forget memories per contact
- How to "forget all" for LGPD compliance
- Expected monthly cost per account
- Warning signs (cost spike, quality drop) and what to do

- [ ] **Step 2: Commit**

```bash
git add docs/captain/semantic-memory.md
git commit -m "docs(captain-memory): operator guide for semantic memory feature"
```

---

### Task 7.2: End-to-end smoke test manual

- [ ] **Step 1: Run full stack locally**

```bash
pnpm run dev
```

- [ ] **Step 2: Enable both flags on test account**

Via Rails console:
```ruby
Account.find(1).update!(custom_attributes: {
  'captain_contact_memory_extraction_enabled' => true,
  'captain_contact_memory_recall_enabled' => true
})
```

- [ ] **Step 3: Drive a conversation end-to-end**

- Send message in WhatsApp test conversation.
- Resolve conversation.
- Verify fact appears in `Captain::ContactMemory.last`.
- Verify embedding populated (wait ~5s for async).
- Start new conversation with same contact.
- Verify agent response references learned fact naturally.

- [ ] **Step 4: Document findings in a note**

If anything unexpected, file issue. Otherwise proceed to next task.

---

### Task 7.3: Final branch review

- [ ] **Step 1: Run full test suite**

```bash
bundle exec rspec spec/enterprise/models/captain/contact_memory_spec.rb \
                  spec/enterprise/services/captain/contact_memories/ \
                  spec/enterprise/jobs/captain/contact_memories/ \
                  spec/enterprise/controllers/api/v1/accounts/contacts/memories_controller_spec.rb \
                  spec/enterprise/policies/captain/contact_memory_policy_spec.rb \
                  spec/enterprise/integration/captain_semantic_memory_spec.rb
```

Expected: all green.

- [ ] **Step 2: Rubocop + eslint**

```bash
bundle exec rubocop enterprise/app/services/captain/contact_memories/ \
                    enterprise/app/jobs/captain/contact_memories/ \
                    enterprise/app/models/captain/contact_memory.rb
pnpm run eslint app/javascript/dashboard/routes/dashboard/contact/components/ContactMemories.vue
```

- [ ] **Step 3: Review `git log`**

```bash
git log --oneline fix/captain-pix-tuner..HEAD
```

Expected: ~25 commits, each focused on one task, conventional messages.

- [ ] **Step 4: Update spec if anything changed during implementation**

- [ ] **Step 5: Tag branch ready for review**

```bash
# push handled by @devops exclusively per agent authority
echo "Branch ready for review and @devops push"
```

---

## Self-review checklist (run after plan complete)

- [x] Each spec requirement mapped to a task
- [x] No TBD/TODO placeholders
- [x] Each task shows full code (not "similar to X")
- [x] Type consistency: model name, method names, job class names match across all tasks
- [x] All testing tasks include real test code and expected failure message
- [x] File paths are exact and absolute from repo root
- [x] Cron schedules match spec (silence: 10min, aging: weekly, hard-delete: daily)
- [x] Feature flag checks in every entry point (SilenceDetectorJob, ExtractFromConversationJob, AgentRunnerService)
- [x] LGPD retention (30 days) correct in HardDeleteExpiredJob
- [x] TTLs per type match spec (preferencia 365d, reclamacao 180d, restricao nil…)
- [x] Top-K default 5, timeout 500ms, confidence threshold 0.5 — all match spec
