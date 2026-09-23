import 'package:client/services.dart';
import 'package:flutter/material.dart';
import 'package:client/features/events/features/live_meeting/features/video/utils/brady_bunch_layout.dart';
import 'package:client/features/events/features/live_meeting/features/video/data/providers/conference_room.dart';
import 'package:client/features/events/features/live_meeting/features/video/presentation/widgets/participant_widget.dart';
import 'package:client/features/events/features/live_meeting/features/video/presentation/widgets/custom_page_view_builder.dart';

import '../../data/providers/agora_room.dart';

class BradyBunchViewWidget extends StatefulWidget {
  const BradyBunchViewWidget({Key? key}) : super(key: key);

  @override
  _BradyBunchViewWidgetState createState() => _BradyBunchViewWidgetState();
}

class _BradyBunchViewWidgetState extends State<BradyBunchViewWidget> {
  final _pageController = PageController();

  final _currentPageNotifier = ValueNotifier<int>(0);

  /// A page holds fewer on a phone, where the same count would leave every
  /// tile too small to read a face in.
  static const int _maxParticipantsPerPageDesktop = 9;
  static const int _maxParticipantsPerPageMobile = 6;

  int get _maxParticipantsPerPage =>
      responsiveLayoutService.isMobile(context)
          ? _maxParticipantsPerPageMobile
          : _maxParticipantsPerPageDesktop;

  List<AgoraParticipant> get participants =>
      ConferenceRoom.watchOrNull(context)?.participants ?? [];

  int _calculateNumberOfPages() {
    return (participants.length / _maxParticipantsPerPage).ceil();
  }

  @override
  void dispose() {
    super.dispose();
    _pageController.dispose();
    _currentPageNotifier.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (participants.isEmpty) {
      return const SizedBox.expand();
    }
    return CustomPageViewBuilder(
      pageController: _pageController,
      currentPageNotifier: _currentPageNotifier,
      pagecount: _calculateNumberOfPages(),
      child: _buildPageView(),
    );
  }

  Widget _buildPageView() {
    return LayoutBuilder(
      builder: (context, constraints) => PageView.builder(
        physics: NeverScrollableScrollPhysics(),
        itemCount: _calculateNumberOfPages(),
        controller: _pageController,
        itemBuilder: (BuildContext context, int index) =>
            _buildParticipantPage(index),
        onPageChanged: (int index) {
          _currentPageNotifier.value = index;
        },
      ),
    );
  }

  Widget _buildParticipantPage(int pageIndex) {
    return RepaintBoundary(
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          // Tiles carry half the gutter each, so without this the grid's outer
          // edge sat at half the margin a featured tile gets. Taken off the
          // layout's width and height too, or the grid would size itself for
          // space the padding has already claimed.
          const outerMargin = kVideoTileMargin / 2;
          final width = constraints.maxWidth - outerMargin * 2;
          final height = constraints.maxHeight - outerMargin * 2;

          final participantsOnThisPageStartIndex =
              pageIndex * _maxParticipantsPerPage;
          final pageParticipants = participants
              .skip(participantsOnThisPageStartIndex)
              .take(_maxParticipantsPerPage)
              .toList();

          return Padding(
            padding: const EdgeInsets.all(outerMargin),
            child: BradyBunchLayoutWidget(
              height: height,
              width: width,
              pageParticipants: pageParticipants,
            ),
          );
        },
      ),
    );
  }
}

class BradyBunchLayoutWidget extends StatelessWidget {
  final double height;
  final double width;
  final List<AgoraParticipant> pageParticipants;

  const BradyBunchLayoutWidget({
    required this.height,
    required this.width,
    required this.pageParticipants,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final BradyBunchLayout layout = BradyBunchLayout.calculateOptimalLayout(
      width: width,
      height: height,
      participantCount: pageParticipants.length,
    );

    AgoraParticipant participantAtIndex(int row, int column) =>
        pageParticipants[layout.columns * row + column];

    double aspectRatioAtIndex(int row, int column) {
      final lastRow = row == layout.rows - 1;
      if (lastRow && pageParticipants.length < layout.rows * layout.columns) {
        return layout.getAdjustedAspectRatio;
      } else {
        return layout.layoutParameters.aspectRatio;
      }
    }

    return Column(
      // Centred so a lone participant sits level with the agenda card beside
      // it. This was top-aligned to stop a too-tall grid clipping at both
      // ends; the layout takes the outer margin off its own width and height
      // now, so it sizes to fit and there is nothing to clip.
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (int i = 0; i < layout.rows; i++)
          Flexible(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: layout.imageSize.height),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (int j = 0; j < layout.layoutParameters.columns; j++)
                    if (pageParticipants.length > layout.columns * i + j)
                      Flexible(
                        child: AspectRatio(
                          aspectRatio: aspectRatioAtIndex(i, j),
                          child: Padding(
                            padding:
                                const EdgeInsets.all(kVideoTileMargin / 2),
                            child: ParticipantWidget(
                              borderRadius:
                                  BorderRadius.circular(kVideoTileRadius),
                              globalKey:
                                  ValueKey(participantAtIndex(i, j).userId),
                              participant: participantAtIndex(i, j),
                            ),
                          ),
                        ),
                      ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
