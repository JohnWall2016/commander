A library for Dart developers.

Created from templates made available by Stagehand under a BSD-style
[license](https://github.com/dart-lang/stagehand/blob/master/LICENSE).

## Usage

A simple usage example:

```dart
import 'package:commander/commander.dart';

main() {
    var program = Command()
    ..setVersion('0.0.1')
    ..setDescription('扶贫数据导库程序');

  program
    .command('pkrk')
    ..setArguments('<date> <xlsx> <beginRow> <endRow>')
    ..setDescription('导入贫困人口数据')
    ..setUsage('201902 D:\\精准扶贫\\201902\\7372人贫困人口台账.xlsx 2 7373')
    ..setAction((args) {
      print(args);
    });

  program
    .command('rdsf')
    ..setArguments('<tabeName> <date> [idcards]')
    ..setDescription('认定居保身份')
    ..setUsage('2019年度扶贫历史数据底册 201902\n       rdsf 201903扶贫数据底册 201903')
    ..setAction((args) {
      print(args);
    });

  program.parse(args);
}
```

## Features and bugs

Please file feature requests and bugs at the [issue tracker][tracker].

[tracker]: http://example.com/issues/replaceme
