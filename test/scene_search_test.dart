import 'package:animax/core/scene_search.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('trace.moe result parsing', () {
    final SceneMatch m = SceneMatch.fromJson(<String, dynamic>{
      'anilist': <String, dynamic>{
        'title': <String, dynamic>{
          'romaji': 'Keroro Gunsou☆',
          'english': 'KERORO☆',
          'native': 'ケロロ軍曹☆',
        },
        'isAdult': false,
      },
      'episode': 1,
      'from': 810.58,
      'to': 812.58,
      'similarity': 0.969,
      'image': 'https://media.trace.moe/image/x.jpg',
    });
    expect(m.title, 'Keroro Gunsou☆');
    expect(m.altTitle, 'KERORO☆');
    expect(m.episode, 1);
    expect(m.from, closeTo(810.58, 0.001));
    expect(m.similarity, greaterThan(SceneSearch.sureSimilarity));
    expect(
      SceneMatch.fromJson(<String, dynamic>{'episode': '3', 'similarity': 0.5})
          .episode,
      3,
    );
  });
}
