import 'package:firebase_admin_interop/firebase_admin_interop.dart';
import 'infra/firestore_utils.dart';
import 'package:data_models/cloud_functions/requests.dart';
import 'package:quiver/iterables.dart';

SendEmailClient sendEmailClient = SendEmailClient();

class SendEmailClient {
  Future<void> sendEmail(
    SendGridEmail email, {
    Transaction? transaction,
  }) async {
    final newDocument = firestore.collection('sendgridmail').document();

    print('Creating email document in sendgridmail collection');
    print('Email to: ${email.to}');
    print('Email from: ${email.from}');
    print('Document ID: ${newDocument.documentID}');

    final newData =
        DocumentData.fromMap(firestoreUtils.toFirestoreJson(email.toJson()));
    if (transaction != null) {
      transaction.create(newDocument, newData);
      print('Email document created in transaction');
    } else {
      await newDocument.setData(newData);
      print('Email document created successfully');
    }
  }

  Future<void> sendEmails(List<SendGridEmail> emails) async {
    print('sendEmails called with ${emails.length} emails');

    if (emails.isEmpty) {
      print('No emails to send - list is empty');
      return;
    }

    print('Creating email documents in sendgridmail collection...');
    await Future.wait(
      partition(emails, 500).map((sublist) {
        print('Processing batch of ${sublist.length} emails');
        final batch = firestore.batch();
        sublist.map((email) {
          final doc = firestore.collection('sendgridmail').document();
          print('Creating document ${doc.documentID} for ${email.to}');
          batch.setData(
            doc,
            DocumentData.fromMap(
              firestoreUtils.toFirestoreJson(email.toJson()),
            ),
          );
        }).toList();
        return batch.commit();
      }).toList(),
    );
    print(
      'All ${emails.length} email documents created successfully in sendgridmail collection',
    );
  }
}
