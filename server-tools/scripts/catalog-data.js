'use strict';
/**
 * البيانات الأساسية: المهن والخدمات والمحافظات.
 * هذه ليست بيانات وهمية — هي الكتالوج المبدئي، ويمكن تعديله بالكامل من لوحة التحكم.
 * icon = اسم أيقونة Material (التطبيق يعرضها)، ويمكن رفع صورة أيقونة من لوحة التحكم.
 */

const categories = [
  { id: 'plumber', nameAr: 'سباك', nameEn: 'Plumber', icon: 'plumbing', services: [
    ['تسريب مياه', 'Water leak'], ['تسليك مواسير وبلاعات', 'Drain unclogging'], ['تركيب خلاط وحنفيات', 'Faucet installation'],
    ['تركيب سخان', 'Water heater installation'], ['تركيب أطقم حمام', 'Bathroom fixtures'], ['تأسيس سباكة', 'Plumbing rough-in'],
  ] },
  { id: 'electrician', nameAr: 'كهربائي', nameEn: 'Electrician', icon: 'electrical_services', services: [
    ['إصلاح عطل كهرباء', 'Electrical fault repair'], ['تركيب نجف وإضاءة', 'Lighting installation'], ['تركيب مفاتيح وبرايز', 'Switches & sockets'],
    ['لوحة كهرباء وقواطع', 'Breaker panel'], ['تأسيس كهرباء', 'Electrical rough-in'], ['تركيب مراوح', 'Fan installation'],
  ] },
  { id: 'carpenter', nameAr: 'نجار', nameEn: 'Carpenter', icon: 'carpenter', services: [
    ['إصلاح أبواب وشبابيك', 'Door & window repair'], ['تركيب مطبخ', 'Kitchen installation'], ['تفصيل دولاب', 'Custom wardrobe'],
    ['إصلاح أثاث', 'Furniture repair'], ['فك وتركيب أثاث', 'Furniture assembly'],
  ] },
  { id: 'painter', nameAr: 'نقاش', nameEn: 'Painter', icon: 'format_paint', services: [
    ['دهان شقة', 'Apartment painting'], ['دهان حائط/غرفة', 'Room painting'], ['ورق حائط', 'Wallpaper'], ['معالجة رطوبة وشروخ', 'Damp & crack treatment'],
  ] },
  { id: 'ac_technician', nameAr: 'فني تكييف', nameEn: 'AC Technician', icon: 'ac_unit', services: [
    ['صيانة تكييف', 'AC maintenance'], ['شحن فريون', 'Freon recharge'], ['تركيب تكييف', 'AC installation'], ['فك ونقل تكييف', 'AC removal & relocation'],
  ] },
  { id: 'mechanic', nameAr: 'ميكانيكي', nameEn: 'Mechanic', icon: 'car_repair', services: [
    ['كشف أعطال', 'Diagnostics'], ['تغيير زيت', 'Oil change'], ['فرامل', 'Brakes'], ['كهرباء سيارات', 'Car electrics'], ['ونش/سحب', 'Towing'],
  ] },
  { id: 'appliances', nameAr: 'فني أجهزة منزلية', nameEn: 'Appliance Technician', icon: 'kitchen', services: [
    ['غسالة', 'Washing machine'], ['ثلاجة', 'Refrigerator'], ['بوتاجاز', 'Gas stove'], ['سخان', 'Water heater'], ['ميكروويف', 'Microwave'],
  ] },
  { id: 'tiles', nameAr: 'مبلط سيراميك', nameEn: 'Tiler', icon: 'grid_on', services: [
    ['تركيب سيراميك وبورسلين', 'Tile installation'], ['ترميم بلاط', 'Tile repair'], ['رخام وجرانيت', 'Marble & granite'],
  ] },
  { id: 'gypsum', nameAr: 'جبس ومحارة', nameEn: 'Gypsum & Plaster', icon: 'construction', services: [
    ['أسقف جبس بورد', 'Gypsum board ceilings'], ['محارة', 'Plastering'], ['ديكورات جبس', 'Gypsum decor'],
  ] },
  { id: 'smith', nameAr: 'حداد ولحام', nameEn: 'Blacksmith & Welding', icon: 'hardware', services: [
    ['لحام', 'Welding'], ['أبواب وشبابيك حديد', 'Iron doors & windows'], ['حماية شبابيك', 'Window guards'],
  ] },
  { id: 'aluminum', nameAr: 'ألوميتال', nameEn: 'Aluminum', icon: 'window', services: [
    ['شبابيك ألوميتال', 'Aluminum windows'], ['مطابخ ألوميتال', 'Aluminum kitchens'], ['إصلاح ألوميتال', 'Aluminum repair'],
  ] },
  { id: 'satellite', nameAr: 'فني دش وشاشات', nameEn: 'Satellite & TV', icon: 'satellite_alt', services: [
    ['تركيب دش', 'Dish installation'], ['ضبط قنوات', 'Channel tuning'], ['تعليق شاشة', 'TV wall mounting'],
  ] },
  { id: 'cleaning', nameAr: 'تنظيف', nameEn: 'Cleaning', icon: 'cleaning_services', services: [
    ['تنظيف شقة', 'Apartment cleaning'], ['تنظيف بعد التشطيب', 'Post-construction cleaning'], ['تنظيف سجاد وأنتريهات', 'Carpet & sofa cleaning'],
  ] },
  { id: 'movers', nameAr: 'نقل عفش', nameEn: 'Movers', icon: 'local_shipping', services: [
    ['نقل عفش', 'Furniture moving'], ['فك وتغليف', 'Packing & disassembly'], ['ونش رفع عفش', 'Furniture hoist'],
  ] },
];

// [code, عربي, English, lat, lng] — الإحداثيات لعاصمة المحافظة (مركز البحث عند الاختيار اليدوي)
const governorates = [
  ['cairo', 'القاهرة', 'Cairo', 30.0444, 31.2357], ['giza', 'الجيزة', 'Giza', 30.0131, 31.2089], ['alexandria', 'الإسكندرية', 'Alexandria', 31.2001, 29.9187],
  ['qalyubia', 'القليوبية', 'Qalyubia', 30.466, 31.1858], ['sharqia', 'الشرقية', 'Sharqia', 30.5877, 31.502], ['dakahlia', 'الدقهلية', 'Dakahlia', 31.0409, 31.3785],
  ['gharbia', 'الغربية', 'Gharbia', 30.7865, 31.0004], ['monufia', 'المنوفية', 'Monufia', 30.5526, 31.009], ['beheira', 'البحيرة', 'Beheira', 31.0341, 30.4682],
  ['kafr_el_sheikh', 'كفر الشيخ', 'Kafr El Sheikh', 31.1107, 30.9388], ['damietta', 'دمياط', 'Damietta', 31.4165, 31.8133], ['port_said', 'بورسعيد', 'Port Said', 31.2653, 32.3019],
  ['ismailia', 'الإسماعيلية', 'Ismailia', 30.5965, 32.2715], ['suez', 'السويس', 'Suez', 29.9668, 32.5498], ['fayoum', 'الفيوم', 'Fayoum', 29.3084, 30.8428],
  ['beni_suef', 'بني سويف', 'Beni Suef', 29.0661, 31.0994], ['minya', 'المنيا', 'Minya', 28.1099, 30.7503], ['assiut', 'أسيوط', 'Assiut', 27.1809, 31.1837],
  ['sohag', 'سوهاج', 'Sohag', 26.5591, 31.6957], ['qena', 'قنا', 'Qena', 26.1551, 32.716], ['luxor', 'الأقصر', 'Luxor', 25.6872, 32.6396], ['aswan', 'أسوان', 'Aswan', 24.0889, 32.8998],
  ['red_sea', 'البحر الأحمر', 'Red Sea', 27.2579, 33.8116], ['new_valley', 'الوادي الجديد', 'New Valley', 25.439, 30.5586], ['matrouh', 'مطروح', 'Matrouh', 31.3543, 27.2373],
  ['north_sinai', 'شمال سيناء', 'North Sinai', 31.1316, 33.7984], ['south_sinai', 'جنوب سيناء', 'South Sinai', 28.2394, 33.617],
];

module.exports = { categories, governorates };
