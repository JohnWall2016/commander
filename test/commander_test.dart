import 'package:commander/commander.dart';

void main(List<String> args) {
  //testTopLevel(args);
  testSubCommand(args);
}

testTopLevel(args) {
  var cmd = Command()
    ..setVersion('0.0.1')
    ..setDescription('财务支付单生成程序')
    ..setArguments('<发放年月> <业务状态>')
    ..setAction((argv) {
      print(argv);
    });

  cmd.on('--help', (args) {
    print('说明\n'+
        '  发放年月: 格式 YYYYMM, 如 201901\n' +
        '  业务状态：0 - 未支付(默认), 1 - 已支付');
  });

  cmd.parse(args);
}

testSubCommand(args) {
  var program = Command()
    ..setVersion('0.0.1')
    ..setDescription('扶贫数据导库程序');

  program
    .command('pkrk')
    ..setArguments('<date> <xlsx> <beginRow> <endRow>')
    ..setDescription('导入贫困人口数据', {
      'date': '导入日期, 格式: yyyymm'
    })
    ..setUsage('201902 D:\\精准扶贫\\201902\\7372人贫困人口台账.xlsx 2 7373')
    ..setAction((args) {
      print(args);
    });

  program
    .command('rdsf')
    ..setArguments('<tabeName> <date> [idcards...]')
    ..setDescription('认定居保身份')
    ..setUsage('2019年度扶贫历史数据底册 201902\n       rdsf 201903扶贫数据底册 201903')
    ..setAction((args) {
      print(args);
    });

  program.parse(args);
}