// =============================================================================
// PUENTE MAESTRO DE IMPORTACIONES (45 LIBRERÍAS PURAS COMPATIBLES CON 3.29.0)
// =============================================================================

import 'package:flutter_riverpod/flutter_riverpod.dart' as riverpod_pkg;

import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:ionicons/ionicons.dart';
import 'package:dotted_border/dotted_border.dart';
import 'package:shimmer/shimmer.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:confetti/confetti.dart';
import 'package:lottie/lottie.dart';

import 'package:drag_and_drop_lists/drag_and_drop_lists.dart' as dnd_pkg;
import 'package:infinite_scroll_pagination/infinite_scroll_pagination.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:toastification/toastification.dart';
import 'package:data_table_2/data_table_2.dart';
import 'package:animated_tree_view/animated_tree_view.dart';
import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:screenshot/screenshot.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:fl_chart/fl_chart.dart';
import 'package:syncfusion_flutter_charts/charts.dart' as sf_charts;
import 'package:graphview/GraphView.dart' as gv_pkg;
import 'package:flutter_map/flutter_map.dart';

import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:mqtt_client/mqtt_client.dart' as mqtt_pkg;
import 'package:hive_ce/hive.dart' as hive_pkg;
import 'package:path/path.dart' as path_pkg;
import 'package:crypto/crypto.dart' as crypto_pkg;
import 'package:json_path/json_path.dart';
import 'package:diff_match_patch/diff_match_patch.dart';
import 'package:csv/csv.dart';
import 'package:archive/archive.dart';
import 'package:uuid/uuid.dart' as uuid_pkg;
import 'package:faker/faker.dart' as faker_pkg;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:highlight/highlight.dart' as hl_pkg;

import 'package:math_expressions/math_expressions.dart' as math_exp;
import 'package:equations/equations.dart' as eq_pkg;
import 'package:units_converter/units_converter.dart' as units_pkg;
import 'package:expressions/expressions.dart' as expr_pkg;
import 'package:latlong2/latlong.dart';
import 'package:timezone/timezone.dart' as tz;

class LibreriasMaestrasSdui {
  static void inicializarGlobales() {
    final dynamic testReferencia = [
      riverpod_pkg.ProviderContainer,
      GoogleFonts.roboto,
      LucideIcons,
      Ionicons.home,
      DottedBorder,
      Shimmer,
      ConfettiWidget,
      Lottie,
      dnd_pkg.DragAndDropList,
      PagingController,
      MasonryGridView,
      Toastification,
      DataTable2,
      TreeView,
      DropdownButton2,
      TableCalendar,
      ScreenshotController,
      QrImageView,
      LineChart,
      sf_charts.SfCartesianChart,
      gv_pkg.Graph,
      FlutterMap,
      http.Client,
      WebSocketChannel,
      mqtt_pkg.MqttClient,
      hive_pkg.Hive,
      path_pkg.Context,
      crypto_pkg.md5,
      JsonPath,
      DiffMatchPatch,
      ListToCsvConverter,
      GZipEncoder,
      uuid_pkg.Uuid,
      faker_pkg.Faker,
      pw.Document,
      MarkdownBody,
      HighlightView,
      hl_pkg.Mode,
      math_exp.Parser,
      eq_pkg.Complex,
      units_pkg.Length,
      expr_pkg.ExpressionEvaluator,
      LatLng,
      tz.Location
    ];
  }
}