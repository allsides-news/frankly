import 'dart:async';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:client/features/events/features/live_meeting/features/video/data/models/networking_status_model.dart';
import 'package:client/features/events/features/live_meeting/features/video/data/providers/agora_room.dart';
import 'package:client/features/events/features/live_meeting/features/video/presentation/networking_status_presenter.dart';
import 'package:client/core/data/services/clock_service.dart';
import 'package:mockito/mockito.dart';

import '../../../../../../../../mocked_classes.mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final mockBuildContext = MockBuildContext();
  final mockView = MockNetworkingStatusView();
  final mockConferenceRoom = MockConferenceRoom();
  final mockEventProvider = MockEventProvider();
  final mockLiveMeetingProvider = MockLiveMeetingProvider();
  final mockRoom = MockAgoraRoom();
  final mockLocalParticipant = MockAgoraParticipant();

  final mockClockService = MockClockService();
  when(mockClockService.now()).thenReturn(DateTime.now());
  GetIt.instance.registerSingleton<ClockService>(mockClockService);

  late NetworkingStatusModel model;
  late NetworkingStatusPresenter presenter;

  setUp(() {
    model = NetworkingStatusModel();
    presenter = NetworkingStatusPresenter(
      mockBuildContext,
      mockView,
      model,
      conferenceRoom: mockConferenceRoom,
    );

    when(mockRoom.channelName).thenReturn('test-channel');
    when(mockRoom.token).thenReturn('token');
    when(mockRoom.liveMeetingProvider).thenReturn(mockLiveMeetingProvider);
    when(mockRoom.eventProvider).thenReturn(mockEventProvider);
    when(mockRoom.conferenceRoom).thenReturn(mockConferenceRoom);
  });

  tearDown(() {
    reset(mockBuildContext);
    reset(mockView);
    reset(mockConferenceRoom);
    reset(mockRoom);
    reset(mockLocalParticipant);
  });

  group('updateNetworkQuality', () {
    group('bad network quality', () {
      test('network quality stays bad after 5s', () async {
        model.isLowNetworkQuality = false;
        expect(model.timer, isNull);

        when(mockConferenceRoom.room).thenReturn(mockRoom);
        when(mockRoom.localParticipant).thenReturn(mockLocalParticipant);
        when(mockLocalParticipant.uplinkQuality)
            .thenReturn(QualityType.qualityBad);
        when(mockLocalParticipant.downlinkQuality)
            .thenReturn(QualityType.qualityGood);

        presenter.updateNetworkQuality();

        await Future.delayed(Duration(seconds: 5));

        expect(model.isLowNetworkQuality, isTrue);
        verify(mockView.updateView()).called(1);
        expect(model.timer!.isActive, isTrue);
      });

      test('network quality changes within 5s', () async {
        model.isLowNetworkQuality = false;
        expect(model.timer, isNull);

        when(mockConferenceRoom.room).thenReturn(mockRoom);
        when(mockRoom.localParticipant).thenReturn(mockLocalParticipant);
        when(mockLocalParticipant.uplinkQuality)
            .thenReturn(QualityType.qualityBad);
        when(mockLocalParticipant.downlinkQuality)
            .thenReturn(QualityType.qualityGood);

        presenter.updateNetworkQuality();

        model.uplinkQuality = QualityType.qualityGood;
        await Future.delayed(Duration(seconds: 5));

        expect(model.isLowNetworkQuality, isFalse);
        verify(mockView.updateView()).called(2);
        expect(model.timer!.isActive, isFalse);
      });

      test('does not check videoEnabled', () async {
        model.isLowNetworkQuality = false;
        expect(model.timer, isNull);

        when(mockConferenceRoom.room).thenReturn(mockRoom);
        when(mockRoom.localParticipant).thenReturn(mockLocalParticipant);
        when(mockLocalParticipant.uplinkQuality)
            .thenReturn(QualityType.qualityBad);
        when(mockLocalParticipant.downlinkQuality)
            .thenReturn(QualityType.qualityGood);

        presenter.updateNetworkQuality();

        // videoEnabled is never accessed
        verifyNever(mockConferenceRoom.videoEnabled);
      });
    });

    group('good network quality', () {
      test('resets isLowNetworkQuality when it was true', () {
        model.isLowNetworkQuality = true;
        model.timer = Timer.periodic(Duration(seconds: 1), (_) {});
        expect(model.timer!.isActive, isTrue);

        when(mockConferenceRoom.room).thenReturn(mockRoom);
        when(mockRoom.localParticipant).thenReturn(mockLocalParticipant);
        when(mockLocalParticipant.uplinkQuality)
            .thenReturn(QualityType.qualityGood);
        when(mockLocalParticipant.downlinkQuality)
            .thenReturn(QualityType.qualityGood);

        presenter.updateNetworkQuality();

        expect(model.isLowNetworkQuality, isFalse);
        verify(mockView.updateView()).called(1);
        expect(model.timer!.isActive, isFalse);
      });

      test('does not call updateView when isLowNetworkQuality was false', () {
        model.isLowNetworkQuality = false;
        model.timer = Timer.periodic(Duration(seconds: 1), (_) {});
        expect(model.timer!.isActive, isTrue);

        when(mockConferenceRoom.room).thenReturn(mockRoom);
        when(mockRoom.localParticipant).thenReturn(mockLocalParticipant);
        when(mockLocalParticipant.uplinkQuality)
            .thenReturn(QualityType.qualityGood);
        when(mockLocalParticipant.downlinkQuality)
            .thenReturn(QualityType.qualityGood);

        presenter.updateNetworkQuality();

        expect(model.isLowNetworkQuality, isFalse);
        verifyNever(mockView.updateView());
        expect(model.timer!.isActive, isFalse);
      });
    });
  });

  group('dismissLowNetworkQualityMessage', () {
    test('is dismissed already', () {
      model.isLowNetworkQualityMessageDismissed = true;
      presenter.dismissLowNetworkQualityMessage();
      expect(model.isLowNetworkQualityMessageDismissed, isTrue);
      expect(model.dismissedAt, isNotNull);
    });

    test('was not dismissed', () {
      model.isLowNetworkQualityMessageDismissed = false;
      presenter.dismissLowNetworkQualityMessage();
      expect(model.isLowNetworkQualityMessageDismissed, isTrue);
      expect(model.dismissedAt, isNotNull);
    });
  });

  test('dispose', () {
    model.timer = Timer.periodic(Duration(seconds: 1), (_) {});
    expect(model.timer!.isActive, isTrue);

    presenter.dispose();

    expect(model.timer!.isActive, isFalse);
  });

  group('getMessage', () {
    test('suggests turning camera off when uplink is bad', () {
      model.uplinkQuality = QualityType.qualityBad;
      model.downlinkQuality = QualityType.qualityGood;

      expect(presenter.getMessage(), contains('Turning off your camera'));
    });

    test('generic message when only downlink is bad', () {
      model.uplinkQuality = QualityType.qualityGood;
      model.downlinkQuality = QualityType.qualityBad;

      expect(presenter.getMessage(), contains('connection is spotty'));
    });

    test('generic message when both directions are bad', () {
      // A starved downlink makes the SDK report the uplink as bad too
      // (bandwidth estimation feedback arrives over the downlink), so the
      // camera-off advice would be misdirected — see getMessage.
      model.uplinkQuality = QualityType.qualityBad;
      model.downlinkQuality = QualityType.qualityVbad;

      expect(presenter.getMessage(), contains('connection is spotty'));
      expect(
        presenter.getMessage(),
        isNot(contains('Turning off your camera')),
      );
    });
  });

  group('getCorrectWidget', () {
    final nothing = SizedBox.shrink();
    final networkStatusAlert = SizedBox.shrink();
    final reconnectingAlert = SizedBox.shrink();

    test('shows nothing when network quality is good', () {
      model.isLowNetworkQuality = false;
      model.isLowNetworkQualityMessageDismissed = false;

      final result = presenter.getCorrectWidget(
        nothing: nothing,
        networkStatusAlert: networkStatusAlert,
        reconnectingAlert: reconnectingAlert,
      );
      expect(result, nothing);
    });

    test('shows alert when network quality is low and not dismissed', () {
      model.isLowNetworkQuality = true;
      model.isLowNetworkQualityMessageDismissed = false;

      final result = presenter.getCorrectWidget(
        nothing: nothing,
        networkStatusAlert: networkStatusAlert,
        reconnectingAlert: reconnectingAlert,
      );
      expect(result, networkStatusAlert);
    });

    test('shows nothing when network quality is low but dismissed', () {
      model.isLowNetworkQuality = true;
      model.isLowNetworkQualityMessageDismissed = true;

      final result = presenter.getCorrectWidget(
        nothing: nothing,
        networkStatusAlert: networkStatusAlert,
        reconnectingAlert: reconnectingAlert,
      );
      expect(result, nothing);
    });

    test('shows nothing when network quality is good and dismissed', () {
      model.isLowNetworkQuality = false;
      model.isLowNetworkQualityMessageDismissed = true;

      final result = presenter.getCorrectWidget(
        nothing: nothing,
        networkStatusAlert: networkStatusAlert,
        reconnectingAlert: reconnectingAlert,
      );
      expect(result, nothing);
    });

    test('reconnecting outranks the quality alert and dismissal', () {
      model.isLowNetworkQuality = true;
      model.isLowNetworkQualityMessageDismissed = true;

      when(mockConferenceRoom.room).thenReturn(mockRoom);
      when(mockRoom.state).thenReturn(AgoraRoomState.RECONNECTING);

      final result = presenter.getCorrectWidget(
        nothing: nothing,
        networkStatusAlert: networkStatusAlert,
        reconnectingAlert: reconnectingAlert,
      );
      expect(result, reconnectingAlert);
    });
  });
}
