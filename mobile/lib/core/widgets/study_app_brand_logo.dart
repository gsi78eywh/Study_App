import "package:flutter/foundation.dart";
import "package:flutter/material.dart";
import "package:dio/dio.dart";
import "package:flutter_svg/flutter_svg.dart";

import "../constants/api_constants.dart";

/// Renders the SVG logo stored in the backend database, with a bundled fallback
/// for first launch, offline use, and deployments whose API is unavailable.
class StudyAppBrandLogo extends StatefulWidget {
  final double size;

  const StudyAppBrandLogo({super.key, this.size = 48});

  @override
  State<StudyAppBrandLogo> createState() => _StudyAppBrandLogoState();
}

class _StudyAppBrandLogoState extends State<StudyAppBrandLogo> {
  static Future<String>? _logoRequest;

  Future<String> _fetchLogo() => Dio()
      .get<String>(
        "${ApiConstants.defaultBaseUrl}/api/v1/branding/logo",
        options: Options(responseType: ResponseType.plain),
      )
      .then((response) => response.data ?? "");

  @override
  Widget build(BuildContext context) {
    // Release builds use the database-backed brand asset. Keep debug widget
    // tests and local previews deterministic and network independent.
    if (!kReleaseMode) {
      return SizedBox.square(
        dimension: widget.size,
        child: SvgPicture.asset("assets/images/studyapp_logo.svg", fit: BoxFit.contain),
      );
    }

    _logoRequest ??= _fetchLogo();
    return SizedBox.square(
      dimension: widget.size,
      child: FutureBuilder<String>(
        future: _logoRequest,
        builder: (context, snapshot) {
          if (snapshot.hasData && snapshot.data!.isNotEmpty) {
            return SvgPicture.string(snapshot.data!, fit: BoxFit.contain);
          }
          return SvgPicture.asset("assets/images/studyapp_logo.svg", fit: BoxFit.contain);
        },
      ),
    );
  }
}
