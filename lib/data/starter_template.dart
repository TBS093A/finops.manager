import '../domain/calendar.dart';
import '../domain/models.dart';
import 'store.dart';

/// Typical positions of a household on B2B, without amounts: the user fills
/// in their own numbers instead of starting from a blank form.
void addStarterTemplate(MemberData me, {YearMonth? from}) {
  final start = from ?? YearMonth.now();

  Expense monthly(String name, String cat, {bool budget = false}) => Expense(
    id: uuid.v4(),
    name: name,
    amount: 0,
    categoryId: cat,
    start: start,
    budget: budget,
  );

  me.expenses.addAll([
    monthly('Księgowość', 'firma'),
    monthly('Czynsz / najem', 'mieszkanie'),
    monthly('Media (prąd, gaz, woda)', 'mieszkanie'),
    monthly('Internet i telefon', 'mieszkanie'),
    monthly('Jedzenie i zakupy', 'codzienne', budget: true),
    monthly('Paliwo / bilety', 'transport'),
    monthly('Oszczędności', 'inwestycje'),
  ]);
}
