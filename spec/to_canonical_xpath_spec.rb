require_relative '../app/lib/guided_crawling/page_parsing'

inputs_outputs = [
  %w[/a/b /a[1]/b[1]],
  %w[/a[2]/b /a[2]/b[1]],
  %w[/a/b[2] /a[1]/b[2]],
  %w[/a[2]/b[2] /a[2]/b[2]]
]

RSpec.describe "try_extract_date" do
  inputs_outputs.each do |input, expected_output|
    it input do
      output = to_canonical_xpath(input)
      expect(output).to eq expected_output
    end
  end
end