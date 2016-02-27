require_relative '../../../cups_helper.rb'

Puppet::Type.type(:cups_queue).provide(:cups) do
  @doc = 'Installs and manages CUPS printer queues.'

  commands(cupsaccept: 'cupsaccept')
  commands(cupsdisable: 'cupsdisable')
  commands(cupsenable: 'cupsenable')
  commands(cupsreject: 'cupsreject')
  commands(ipptool: 'ipptool') # Used in cups_helper. Declared here for Puppet's provider suitability mechanism
  commands(lpadmin: 'lpadmin')
  commands(lpoptions: 'lpoptions')

  ### Static provider methods

  def self.instances
    providers = []
    Facter.value(:cups_classmembers).each do |classname, membernames|
      providers << new(name: classname, ensure: :class, members: membernames)
    end
    Facter.value(:cups_printers).each do |printername|
      providers << new(name: printername, ensure: :printer)
    end
    providers
  end

  def self.prefetch(specified)
    discovered = instances
    specified.keys.each do |name|
      provider = discovered.find { |instance| instance.name == name }
      specified[name].provider = provider if provider
    end
  end

  ### Existence

  def class_exists?
    Facter.value(:cups_classes).include? name
  end

  def printer_exists?
    Facter.value(:cups_printers).include? name
  end

  def queue_exists?
    class_exists? || printer_exists?
  end

  ### Creation and destruction

  def create_class
    destroy
    resource.should(:members).each { |member| lpadmin('-E', '-p', member, '-c', name) }
    [:description, :location, :shared,
     :enabled, :held, :accepting].each do |property|
      setter = (property.to_s + '=').to_sym
      value = resource.should(property)
      method(setter).call(value) if value
    end
  end

  def create_printer
    destroy
    [:interface, :model, :ppd, :uri,
     :description, :location, :shared,
     :enabled, :held, :accepting].each do |property|
      setter = (property.to_s + '=').to_sym
      value = resource.value(property)
      method(setter).call(value) if value
    end
  end

  def destroy
    lpadmin('-E', '-x', name) if queue_exists?
  end

  ### Property getters and setters

  def ensure
    prefetched = @property_hash[:ensure]
    prefetched ? prefetched : :absent
  end

  def accepting
    query('printer-is-accepting-jobs')
  end

  def accepting=(value)
    value == :true ? cupsaccept('-E', name) : cupsreject('-E', name)
  end

  def description
    query('printer-info')
  end

  def description=(value)
    lpadmin('-E', '-p', name, '-D', value)
  end

  def enabled
    query('printer-state') == 'stopped' ? :false : :true
  end

  def enabled=(value)
    value == :true ? cupsenable('-E', name) : cupsdisable('-E', name)
  end

  def held
    query('printer-state-reasons') =~ /hold-new-jobs/ ? :true : :false
  end

  def held=(value)
    value == :true ? cupsdisable('-E', '--hold', name) : cupsenable('-E', '--release', name)
  end

  def interface=(value)
    lpadmin('-E', '-p', name, '-i', value)
  end

  def location
    query('printer-location')
  end

  def location=(value)
    lpadmin('-E', '-p', name, '-L', value)
  end

  def make_and_model
    query('printer-make-and-model')
  end

  def make_and_model=(_value)
    create_printer if printer?
    create_class if class?
  end

  def model=(value)
    lpadmin('-E', '-p', name, '-m', value)
  end

  def members
    prefetched = @property_hash[:members]
    prefetched if prefetched
  end

  def members=(_value)
    create_class
  end

  def options
    options_should = resource.should(:options)
    options_should.nil? ? all_options_is : specified_options_is(options_should)
  end

  def options=(options_should)
    options_should.each do |key, value|
      lpadmin('-E', '-p', name, '-o', "#{key}=#{value}")
    end
  end

  def ppd=(value)
    lpadmin('-E', '-p', name, '-P', value)
  end

  def shared
    query('printer-is-shared')
  end

  def shared=(value)
    lpadmin('-E', '-p', name, '-o', "printer-is-shared=#{value}")
  end

  def uri
    query('device-uri') if printer?
  end

  def uri=(value)
    lpadmin('-E', '-p', name, '-v', value)
  end

  private

  def class?
    self.ensure == :class
  end

  def printer?
    self.ensure == :printer
  end

  def query(property)
    Cups::Queue::Attribute.query(name, property)
  end

  def specified_options_is(options_should)
    answer = {}
    supported_options_is = all_options_is

    options_should.keys.each do |key|
      if supported_options_is.key? key
        answer[key] = supported_options_is[key]
      else
        fail("Managing the option '#{key}' is unsupported.")
      end
    end

    answer
  end

  def all_options_is
    cups_options.merge(ppd_options)
  end

  def cups_options
    answer = {}

    options = %w(job-k-limit job-page-limit job-quota-period job-sheets-default port-monitor printer-error-policy printer-op-policy)
    options.each { |option| answer[option] = query(option) }

    answer
  end

  def ppd_options
    answer = {}

    lpoptions('-E', '-p', name, '-l').each_line do |line|
      result = %r{\A(?<key>\w+)/(.*):(.*)\*(?<value>\w+)}.match(line)
      answer[result[:key]] = result[:value] if result
    end

    answer
  end
end