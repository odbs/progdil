require 'pathname'     #dosya yoluyla metod calıştırılır
require 'pythonconfig' #modül import edilmesi
require 'yaml'         #işlenecek verilerin dosyası
    
CONFIG = Config.fetch('presentation', {})  #dosyayı config'e atar

PRESENTATION_DIR = CONFIG.fetch('directory', 'p')#key olarak dizin ,value ise p olarak alınır
DEFAULT_CONFFILE = CONFIG.fetch('conffile', '_templates/presentation.cfg')
INDEX_FILE = File.join(PRESENTATION_DIR, 'index.html')#dizinin yolu atanır
IMAGE_GEOMETRY = [ 733, 550 ] #resim boyutu
DEPEND_KEYS    = %w(source css js) #bağlı anahtar
DEPEND_ALWAYS  = %w(media) #sürekli bağımlılık
TASKS = {
    :index   => 'sunumları indeksle',
    :build   => 'sunumları oluştur',
    :clean   => 'sunumları temizle',
    :view    => 'sunumları görüntüle',
    :run     => 'sunumları sun',
    :optim   => 'resimleri iyileştir',
    :default => 'öntanımlı görev',
}

presentation   = {}
tag            = {}

class File #sınıf yapısıyla dosya yolu alma
  @@absolute_path_here = Pathname.new(Pathname.pwd)
  def self.to_herepath(path)
    Pathname.new(File.expand_path(path)).relative_path_from(@@absolute_path_here).to_s
  end
  def self.to_filelist(path)
    File.directory?(path) ?
      FileList[File.join(path, '*')].select { |f| File.file?(f) } :
      [path]
  end
end
 #dosya youyla slayt yorumlama 
def png_comment(file, string)
  require 'chunky_png'
  require 'oily_png'
 #acılan dosyaya kaydedildi notu döner
  image = ChunkyPNG::Image.from_file(file)
  image.metadata['Comment'] = 'raked'
  image.save(file)
end
 #slayt boyutu optimize edilir
def png_optim(file, threshold=40000)
  return if File.new(file).size < threshold
  sh "pngnq -f -e .png-nq #{file}" #yorum satırında calıştırılacak komut
  out = "#{file}-nq"
  if File.exist?(out) #dosya kontrol edilir,file ile değiştirilir,out dosyası silinir
    $?.success? ? File.rename(out, file) : File.delete(out)
  end
  png_comment(file, 'raked') #işlendi notu düş
end
 #dosya boyutunun optimize edilir
def jpg_optim(file)
  sh "jpegoptim -q -m80 #{file}"
  sh "mogrify -comment 'raked' #{file}"
end
 #jpg png dosyalarını listele
def optim
  pngs, jpgs = FileList["**/*.png"], FileList["**/*.jpg", "**/*.jpeg"]
 #alınan dosyaları istenen uzantılarda çıkart
  [pngs, jpgs].each do |a|
    a.reject! { |f| %x{identify -format '%c' #{f}} =~ /[Rr]aked/ }
  end
 #slaytların boyutunu dezenleme
  (pngs + jpgs).each do |f|
    w, h = %x{identify -format '%[fx:w] %[fx:h]' #{f}}.split.map { |e| e.to_i } #boyutlar belirlenir
    size, i = [w, h].each_with_index.max
    if size > IMAGE_GEOMETRY[i] #istenilen boyuta cevrilir
      arg = (i > 0 ? 'x' : '') + IMAGE_GEOMETRY[i].to_s
      sh "mogrify -resize #{arg} #{f}"
    end
  end

  pngs.each { |f| png_optim(f) }
  jpgs.each { |f| jpg_optim(f) }

  (pngs + jpgs).each do |f|
    name = File.basename f
    FileList["*/*.md"].each do |src|
      sh "grep -q '(.*#{name})' #{src} && touch #{src}"
    end
  end
end

default_conffile = File.expand_path(DEFAULT_CONFFILE)
 #dosya yollarını al
FileList[File.join(PRESENTATION_DIR, "[^_.]*")].each do |dir|
  next unless File.directory?(dir)
  chdir dir do #dosya uzantılarının ayarlaması
    name = File.basename(dir)
    conffile = File.exists?('presentation.cfg') ? 'presentation.cfg' : default_conffile
    config = File.open(conffile, "r") do |f|
      PythonConfig::ConfigParser.new(f)
    end
 #yoksa hata yaz ve cik
    landslide = config['landslide']
    if ! landslide
      $stderr.puts "#{dir}: 'landslide' bölümü tanımlanmamış"
      exit 1
    end
 
    if landslide['destination']
      $stderr.puts "#{dir}: 'destination' ayarı kullanılmış; hedef dosya belirtilmeyin"
      exit 1
    end
 #dosya varlığının sorgulanması
    if File.exists?('index.md')
      base = 'index'
      ispublic = true
    elsif File.exists?('presentation.md')
      base = 'presentation'
      ispublic = false
    else
      $stderr.puts "#{dir}: sunum kaynağı 'presentation.md' veya 'index.md' olmalı"
      exit 1
    end

    basename = base + '.html'
    thumbnail = File.to_herepath(base + '.png') #png ile başlangıç yolu belirlenir
    target = File.to_herepath(basename)
 #dosyalar bağımlı hale getitilir
    deps = []
    (DEPEND_ALWAYS + landslide.values_at(*DEPEND_KEYS)).compact.each do |v|
      deps += v.split.select { |p| File.exists?(p) }.map { |p| File.to_filelist(p) }.flatten
    end

    deps.map! { |e| File.to_herepath(e) }
    deps.delete(target)
    deps.delete(thumbnail)
 #etiketleme
    tags = []

   presentation[dir] = {
      :basename  => basename,	# üreteceğimiz sunum dosyasının baz adı
      :conffile  => conffile,	# landslide konfigürasyonu (mutlak dosya yolu)
      :deps      => deps,	# sunum bağımlılıkları
      :directory => dir,	# sunum dizini (tepe dizine göreli)
      :name      => name,	# sunum ismi
      :public    => ispublic,	# sunum dışarı açık mı
      :tags      => tags,	# sunum etiketleri
      :target    => target,	# üreteceğimiz sunum dosyası (tepe dizine göreli)
      :thumbnail => thumbnail, 	# sunum için küçük resim
    }
  end
end
 #bos olan etiketlerin doldurulması
presentation.each do |k, v|
  v[:tags].each do |t|
    tag[t] ||= []
    tag[t] << k
  end
end
 #görev haritalarının olusturulması
tasktab = Hash[*TASKS.map { |k, v| [k, { :desc => v, :tasks => [] }] }.flatten]

presentation.each do |presentation, data|  #dolas ve etiketle
  ns = namespace presentation do
    file data[:target] => data[:deps] do |t|
      chdir presentation do
        sh "landslide -i #{data[:conffile]}"
        sh 'sed -i -e "s/^\([[:blank:]]*var hiddenContext = \)false\(;[[:blank:]]*$\)/\1true\2/" presentation.html'
        unless data[:basename] == 'presentation.html'
          mv 'presentation.html', data[:basename]
        end
      end
    end
 #resimlerin işlenmesi
    file data[:thumbnail] => data[:target] do
      next unless data[:public]
      sh "cutycapt " +
          "--url=file://#{File.absolute_path(data[:target])}#slide1 " +
          "--out=#{data[:thumbnail]} " +
          "--user-style-string='div.slides { width: 900px; overflow: hidden; }' " +
          "--min-width=1024 " +
          "--min-height=768 " +
          "--delay=1000"
      sh "mogrify -resize 240 #{data[:thumbnail]}"
      png_optim(data[:thumbnail])
    end
 #tanımlı optimizasyon işlenmesi
    task :optim do
      chdir presentation do
        optim
      end
    end
 #rake file daki index belili bağımlılıkla calıştırılır
    task :index => data[:thumbnail]
 #optim olrak belirtilen bağımlılıklar calıştırılır
    task :build => [:optim, data[:target], :index]
 #dosya olusturulması
    task :view do
      if File.exists?(data[:target])
        sh "touch #{data[:directory]}; #{browse_command data[:target]}"
      else
        $stderr.puts "#{data[:target]} bulunamadı; önce inşa edin"
      end
    end
 #built ve view calıştırılır
    task :run => [:build, :view]
 #görevi biten bilgiler temizlenir
    task :clean do
      rm_f data[:target]
      rm_f data[:thumbnail]
    end
 #öntanımlı olarak inşa işlemi gercekleşir
    task :default => :build
  end

  ns.tasks.map(&:to_s).each do |t|
    _, _, name = t.partition(":").map(&:to_sym)
    next unless tasktab[name]
    tasktab[name][:tasks] << t
  end
end
 #isim uzayının elemenlarna yeni görev atanır
namespace :p do
  tasktab.each do |name, info|
    desc info[:desc]
    task name => info[:tasks]
    task name[0] => name
  end

  task :build do
    index = YAML.load_file(INDEX_FILE) || {} #yaml dosyasını indexe ata
    presentations = presentation.values.select { |v| v[:public] }.map { |v| v[:directory] }.sort
    unless index and presentations == index['presentations']
      index['presentations'] = presentations
      File.open(INDEX_FILE, 'w') do |f|
        f.write(index.to_yaml)
        f.write("---\n")
      end
    end
  end
 #acıklama eklenmesi
  desc "sunum menüsü"
  task :menu do #sunum adi ve oluşturma tarihi belirlenip gösterilmesi
    lookup = Hash[
      *presentation.sort_by do |k, v| 
        File.mtime(v[:directory])
      end
      .reverse   #map ters cevriliyor
      .map { |k, v| [v[:name], k] }
      .flatten
    ]
 #menüde işlemin renginin ve özelliklerinin ayarlanması
    name = choose do |menu|
      menu.default = "1"
      menu.prompt = color(
        'Lütfen sunum seçin ', :headline
      ) + '[' + color("#{menu.default}", :special) + ']'
      menu.choices(*lookup.keys)
    end
    directory = lookup[name]
    Rake::Task["#{directory}:run"].invoke #rake verilen dizin ile  calıştırılır
  end
  task :m => :menu
end
 #menüde p ile presantationdan gelen veriyle calıştır
desc "sunum menüsü"
task :p => ["p:menu"] 
task :presentation => :p
