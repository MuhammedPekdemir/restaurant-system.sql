#Restaurant Table Tracking System

SQL Server üzerinde geliştirilmiş rezervasyon ve masa yönetim sistemi.


**Proje Hakkında**

Akademik grup projesi için hazırladığım veritabanı sistemi. 

İş mantığının büyük bir kısmı, veri bütünlüğünü korumak adına SQL katmanında (Trigger / Stored Procedure) kurgulanmıştır.


**Özellikler**

Müşteri kayıt ve giriş sistemi
Admin paneli (tek hesap modeli)
Masa ekleme, aktif/pasif yönetimi
3 saatlik saat dilimleriyle rezervasyon (09:00 - 00:00)
Günlük masa doluluk takibi


**Notlar**

Test verisindeki '********' şifreler semboliktir, gerçek kullanımda uygulama katmanında hashlenmelidir.
Sistem tek admin hesabıyla çalışacak şekilde tasarlanmıştır.
