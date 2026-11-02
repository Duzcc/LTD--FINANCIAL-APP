// Ngân hàng hỗ trợ VietQR (mã BIN theo NAPAS, nguồn: api.vietqr.io/v2/banks).
// Danh sách này khớp với frontend: lib/core/banking/vietqr.dart
const BANKS = [
  { bin: '970436', code: 'VCB', name: 'Vietcombank' },
  { bin: '970415', code: 'ICB', name: 'VietinBank' },
  { bin: '970418', code: 'BIDV', name: 'BIDV' },
  { bin: '970405', code: 'VBA', name: 'Agribank' },
  { bin: '970422', code: 'MB', name: 'MBBank' },
  { bin: '970407', code: 'TCB', name: 'Techcombank' },
  { bin: '970416', code: 'ACB', name: 'ACB' },
  { bin: '970432', code: 'VPB', name: 'VPBank' },
  { bin: '970423', code: 'TPB', name: 'TPBank' },
  { bin: '970403', code: 'STB', name: 'Sacombank' },
  { bin: '970437', code: 'HDB', name: 'HDBank' },
  { bin: '970441', code: 'VIB', name: 'VIB' },
  { bin: '970443', code: 'SHB', name: 'SHB' },
  { bin: '970431', code: 'EIB', name: 'Eximbank' },
  { bin: '970426', code: 'MSB', name: 'MSB' },
  { bin: '970448', code: 'OCB', name: 'OCB' },
  { bin: '970440', code: 'SEAB', name: 'SeABank' },
  { bin: '970449', code: 'LPB', name: 'LPBank' },
  { bin: '970428', code: 'NAB', name: 'Nam A Bank' },
  { bin: '546034', code: 'CAKE', name: 'CAKE by VPBank' },
  { bin: '963388', code: 'TIMO', name: 'Timo' },
];
const bankByBin = (bin) => BANKS.find((b) => b.bin === bin) || null;
module.exports = { BANKS, bankByBin };
