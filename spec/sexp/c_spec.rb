require 'spec_helper'

describe Travis::Build::Script::C, :sexp do
  let(:data) { PAYLOADS[:push].deep_clone }

  subject { described_class.new(data).sexp }

  # after :all { store_example }

  it_behaves_like 'a build script sexp'

  it 'sets CC' do
    should include_sexp [:export, ['CC', 'gcc'], echo: true]
  end

  it 'announces gcc --version' do
    should include_sexp [:cmd, 'gcc --version', echo: true]
  end

  it 'runs ./configure && make && make test' do
    should include_sexp [:cmd, './configure && make && make test', echo: true, timing: true]
  end

  describe '#cache_slug' do
    subject { described_class.new(data).cache_slug }
    it { should eq('cache--compiler-gcc') }
  end
end

