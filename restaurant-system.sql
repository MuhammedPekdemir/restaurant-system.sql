
--  RESTORAN MASA TAKİP SİSTEMİ

CREATE DATABASE RestoranMasaTakipDatabase;
GO
USE RestoranMasaTakipDatabase;
GO

--  TABLOLAR

CREATE TABLE MUSTERI (
    MusteriID    INT IDENTITY(1,1) PRIMARY KEY,
    Ad            VARCHAR(50) NOT NULL,
    Soyad         VARCHAR(50) NOT NULL,
    KullaniciAdi VARCHAR(50) NOT NULL UNIQUE, -- Kayıt aşamasında alınır, giriş için kullanılır. Benzersizdir.
    Telefon      VARCHAR(20) NOT NULL UNIQUE, -- Kayıt aşamasında alınır, giriş aşamasında kullanılmaz. Benzersizdir.
    Sifre        VARCHAR(255) NOT NULL,       -- Kayıt aşamasında alınır, giriş kontrolü sağlar.
    KayitTarihi  DATETIME DEFAULT GETDATE()
);

-- Sistem yönetimi için tek bir admin hesabı kullanılacak.
CREATE TABLE ADMIN_HESAP (
    AdminID      INT IDENTITY(1,1) PRIMARY KEY,
    KullaniciAdi VARCHAR(50) NOT NULL UNIQUE,
    Sifre        VARCHAR(255) NOT NULL, 
    SonGiris     DATETIME
);
GO


CREATE TABLE MASA (
    MasaID   INT IDENTITY(1,1) PRIMARY KEY,
    Kapasite INT NOT NULL,
    Aktif    BIT NOT NULL DEFAULT 1
);

CREATE TABLE MASA_GUNLUK_DURUM (
    DurumID    INT  IDENTITY(1,1) PRIMARY KEY,
    MasaID     INT  NOT NULL FOREIGN KEY REFERENCES MASA(MasaID), -- REFERENCES komutu MasaID'nin durumunu kontrol eder.
    Tarih      DATE NOT NULL,
    Saat_09_12 BIT  NOT NULL DEFAULT 0, -- 0: Boş, 1: Dolu
    Saat_12_15 BIT  NOT NULL DEFAULT 0,
    Saat_15_18 BIT  NOT NULL DEFAULT 0,
    Saat_18_21 BIT  NOT NULL DEFAULT 0,
    Saat_21_00 BIT  NOT NULL DEFAULT 0,
    CONSTRAINT UQ_MasaTarih UNIQUE (MasaID, Tarih) -- Aynı masa ve gün için tekrar eden kaydı engeller.
);


CREATE TABLE REZERVASYON (
    RezID INT IDENTITY(1,1) PRIMARY KEY,
    MusteriID  INT NOT NULL FOREIGN KEY REFERENCES MUSTERI(MusteriID),
    MasaID   INT NOT NULL FOREIGN KEY REFERENCES MASA(MasaID),
    Tarih      DATE NOT NULL,
    SaatDilimNo  TINYINT NOT NULL, -- 1:09.00-12.00 | 2:12.00-15.00 | 3:15.00-18.00 | 4:18.00-21.00 | 5:21.00-00.00
                                   -- Saat dilimleri 3 saatlik olarak ayrılmıştır. Restoran 3 saatlik dilimlerde hizmet vermektedir.
    KisiSayisi   INT NOT NULL DEFAULT 1,
    KaporaTutari DECIMAL(10,2) NOT NULL DEFAULT 150.00, -- Standart kapora tutarı sonrasında değiştirilebilir.

    CONSTRAINT CHK_DilimNo CHECK (SaatDilimNo BETWEEN 1 AND 5), -- CHECK komutu ile sınır belirtilir. Bu sayede geçerli saat dilimlerinin dışına çıkılmaz.
    CONSTRAINT CHK_KisiSayisi CHECK (KisiSayisi >= 1),
    CONSTRAINT UQ_Rezervasyon UNIQUE (MasaID, Tarih, SaatDilimNo) -- Saat dilimi çakışmasını engeller.
);
GO

--  TRIGGER

-- Rezervasyon kaydı sonrası ilgili zaman dilimini dolu olarak günceller
CREATE TRIGGER trg_SlotKapat
ON REZERVASYON
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON; -- Gereksiz bilgi döndürülmemesi için NOCOUNT komutu aktif edildi.

    -- Tarih kaydı mevcut değilse yeni satır oluşturur.
    INSERT INTO MASA_GUNLUK_DURUM (MasaID, Tarih)
    SELECT i.MasaID, i.Tarih FROM inserted i
    WHERE NOT EXISTS (
        SELECT * FROM MASA_GUNLUK_DURUM d
        WHERE d.MasaID = i.MasaID AND d.Tarih = i.Tarih  
    );

    -- İlgili zaman dilimini aktif hale getirir.
    UPDATE d SET
        Saat_09_12 = CASE WHEN i.SaatDilimNo=1 THEN 1 ELSE d.Saat_09_12 END,
        Saat_12_15 = CASE WHEN i.SaatDilimNo=2 THEN 1 ELSE d.Saat_12_15 END,
        Saat_15_18 = CASE WHEN i.SaatDilimNo=3 THEN 1 ELSE d.Saat_15_18 END,
        Saat_18_21 = CASE WHEN i.SaatDilimNo=4 THEN 1 ELSE d.Saat_18_21 END,
        Saat_21_00 = CASE WHEN i.SaatDilimNo=5 THEN 1 ELSE d.Saat_21_00 END
    FROM MASA_GUNLUK_DURUM d
    INNER JOIN inserted i ON d.MasaID=i.MasaID AND d.Tarih=i.Tarih;
END;
GO

-- Rezervasyon iptali sonrası ilgili zaman dilimini boş olarak günceller
CREATE TRIGGER trg_SlotAc
ON REZERVASYON
AFTER DELETE
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE d SET
        Saat_09_12 = CASE WHEN i.SaatDilimNo=1 THEN 0 ELSE d.Saat_09_12 END,
        Saat_12_15 = CASE WHEN i.SaatDilimNo=2 THEN 0 ELSE d.Saat_12_15 END,
        Saat_15_18 = CASE WHEN i.SaatDilimNo=3 THEN 0 ELSE d.Saat_15_18 END,
        Saat_18_21 = CASE WHEN i.SaatDilimNo=4 THEN 0 ELSE d.Saat_18_21 END,
        Saat_21_00 = CASE WHEN i.SaatDilimNo=5 THEN 0 ELSE d.Saat_21_00 END
    FROM MASA_GUNLUK_DURUM d
    INNER JOIN deleted i ON d.MasaID=i.MasaID AND d.Tarih=i.Tarih;
END;
GO

-- Rezervasyon öncesi masa aktiflik ve kapasite kontrollerini sağlanır.
CREATE TRIGGER trg_RezervasyonKontrol
ON REZERVASYON
INSTEAD OF INSERT
AS
BEGIN
    SET NOCOUNT ON;

    -- Masa durumunu kontrol eder.
    IF EXISTS (SELECT * FROM inserted i INNER JOIN MASA m ON m.MasaID=i.MasaID WHERE m.Aktif=0)
    BEGIN RAISERROR('Hata: Masa hizmete açık değil!', 16, 1); RETURN; END  -- PRİNT komutunu kullanırsak sistem sorunu yazıp çalışmaya devam eder
                                                                           -- RAISERROR komutunda sorun varsa sistem kendini kapatır. Bu sayede sistemde peşpeşe sorunlar ortaya çıkmaz.   
    
    -- Kişi sayısını kontrol eder.
    IF EXISTS (
        SELECT * FROM inserted i
        INNER JOIN MASA m ON m.MasaID=i.MasaID
        WHERE i.KisiSayisi > m.Kapasite) 
    BEGIN RAISERROR('Hata: Kişi sayısı masa kapasitesini aşıyor!', 16, 1); RETURN; END 

    -- Kontroller başarılıysa veriyi kaydeder
    INSERT INTO REZERVASYON (MusteriID, MasaID, Tarih, SaatDilimNo, KisiSayisi, KaporaTutari)
    SELECT MusteriID, MasaID, Tarih, SaatDilimNo, KisiSayisi, KaporaTutari
    FROM inserted;
END;
GO

-- Aktif rezervasyonu bulunan masaların silinmesini engeller
CREATE TRIGGER trg_MasaSilmeKoru
ON MASA
INSTEAD OF DELETE
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (
        SELECT * FROM deleted d INNER JOIN REZERVASYON r ON r.MasaID=d.MasaID
    )
    BEGIN RAISERROR('Hata: Rezervasyonu bulunan masa silinemez!', 16, 1); RETURN; END

    DELETE FROM MASA WHERE MasaID IN (SELECT MasaID FROM deleted);
END;
GO

-- Aktif rezervasyonu bulunan müşterilerin silinmesini engeller
CREATE TRIGGER trg_MusteriSilmeKoru
ON MUSTERI
INSTEAD OF DELETE
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (
        SELECT * FROM deleted d INNER JOIN REZERVASYON r ON r.MusteriID=d.MusteriID)
    BEGIN RAISERROR('Hata: Rezervasyonu bulunan müşteri silinemez.', 16, 1); 
    RETURN; 
    END

    DELETE FROM MUSTERI WHERE MusteriID IN (SELECT MusteriID FROM deleted);
END;
GO

--  STORED PROCEDURE

CREATE PROCEDURE sp_RezervasyonEkle
    @MusteriID INT, @MasaID INT, @Tarih DATE, @SaatDilimNo TINYINT, @KisiSayisi INT
AS
BEGIN
    SET NOCOUNT ON;
    -- Masa durum kontrolü
    IF NOT EXISTS (SELECT * FROM MASA WHERE MasaID=@MasaID AND Aktif=1)
        BEGIN RAISERROR('Masa aktif değil.', 16, 1); RETURN; END
    -- Saat dilimi doluluk kontrolü
    IF EXISTS (SELECT * FROM REZERVASYON WHERE MasaID=@MasaID AND Tarih=@Tarih AND SaatDilimNo=@SaatDilimNo)
        BEGIN RAISERROR('Seçilen saat dilimi dolu.', 16, 1); RETURN; END

    INSERT INTO REZERVASYON (MusteriID, MasaID, Tarih, SaatDilimNo, KisiSayisi)
    OUTPUT inserted.RezID
    VALUES (@MusteriID, @MasaID, @Tarih, @SaatDilimNo, @KisiSayisi);
END;
GO


CREATE PROCEDURE sp_RezervasyonIptal
    @RezID INT
AS
BEGIN
    SET NOCOUNT ON;
    
    IF NOT EXISTS (SELECT * FROM REZERVASYON WHERE RezID=@RezID)
        BEGIN RAISERROR('Rezervasyon kaydı bulunamadı.', 16, 1); RETURN; END

    DELETE FROM REZERVASYON WHERE RezID=@RezID;
END;
GO


CREATE PROCEDURE sp_MusteriEkle
@Ad VARCHAR(50), @Soyad VARCHAR(50), @Telefon VARCHAR(20),@Kadi VARCHAR(50), @Sifre VARCHAR(255)
AS
BEGIN
    SET NOCOUNT ON;

    -- Bilgilerin doğruluğunu, var olup olmadığını kontrol ediyor.
    IF EXISTS (SELECT * FROM MUSTERI WHERE Telefon=@Telefon OR KullaniciAdi=@Kadi)
    BEGIN 
        RAISERROR('Telefon numarası veya kullanıcı adı sistemde mevcut.', 16, 1); 
        RETURN; 
    END

    INSERT INTO MUSTERI (Ad, Soyad, Telefon, KullaniciAdi, Sifre) 
    VALUES (@Ad, @Soyad, @Telefon, @Kadi, @Sifre);

    -- Yeni kaydın bilgisini getirir.
    SELECT SCOPE_IDENTITY() AS YeniMusteriID;
END;
GO


CREATE PROCEDURE sp_MusteriGiris 
@Kadi VARCHAR(50), @Sifre VARCHAR(255)
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (SELECT * FROM MUSTERI WHERE KullaniciAdi=@Kadi AND Sifre=@Sifre)
    BEGIN
        SELECT MusteriID, Ad, Soyad, 'Giriş Başarılı' AS Mesaj FROM MUSTERI WHERE KullaniciAdi=@Kadi;
    END
    ELSE
    BEGIN RAISERROR('Kullanıcı adı veya şifre hatalı.', 16, 1); END
END;
GO


CREATE PROCEDURE sp_AdminGiris
@Kadi VARCHAR(50), @Sifre VARCHAR(255)
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (SELECT * FROM ADMIN_HESAP WHERE KullaniciAdi=@Kadi AND Sifre=@Sifre)
    BEGIN
        UPDATE ADMIN_HESAP SET SonGiris = GETDATE() WHERE KullaniciAdi=@Kadi;
        SELECT AdminID, 'Giriş Başarılı' AS Mesaj FROM ADMIN_HESAP WHERE KullaniciAdi=@Kadi;
    END
    ELSE
    BEGIN RAISERROR('Yönetici bilgileri hatalı.', 16, 1); END
END;
GO


CREATE PROCEDURE sp_GunlukDoluluk
    @Tarih DATE
AS
BEGIN
    SET NOCOUNT ON;

    SELECT m.MasaID, m.Kapasite,
        COALESCE(d.Saat_09_12,0) AS [09-12],
        COALESCE(d.Saat_12_15,0) AS [12-15],
        COALESCE(d.Saat_15_18,0) AS [15-18],
        COALESCE(d.Saat_18_21,0) AS [18-21],
        COALESCE(d.Saat_21_00,0) AS [21-00]
    FROM MASA m
    LEFT JOIN MASA_GUNLUK_DURUM d ON d.MasaID=m.MasaID AND d.Tarih=@Tarih
    WHERE m.Aktif=1
    ORDER BY m.MasaID;
END;
GO


CREATE PROCEDURE sp_BosSaatler
    @Tarih DATE
AS
BEGIN
    SET NOCOUNT ON;

    SELECT m.MasaID, m.Kapasite,
        CASE WHEN COALESCE(d.Saat_09_12,0)=0 THEN 'BOS' ELSE 'DOLU' END AS [09-12],
        CASE WHEN COALESCE(d.Saat_12_15,0)=0 THEN 'BOS' ELSE 'DOLU' END AS [12-15],
        CASE WHEN COALESCE(d.Saat_15_18,0)=0 THEN 'BOS' ELSE 'DOLU' END AS [15-18],
        CASE WHEN COALESCE(d.Saat_18_21,0)=0 THEN 'BOS' ELSE 'DOLU' END AS [18-21],
        CASE WHEN COALESCE(d.Saat_21_00,0)=0 THEN 'BOS' ELSE 'DOLU' END AS [21-00]
    FROM MASA m
    LEFT JOIN MASA_GUNLUK_DURUM d ON d.MasaID=m.MasaID AND d.Tarih=@Tarih
    WHERE m.Aktif=1
    ORDER BY m.MasaID;
END;
GO


CREATE PROCEDURE sp_MasaAktifPasif
    @MasaID INT, @Durum BIT
AS
BEGIN
    SET NOCOUNT ON;

    -- Gelecekteki rezervasyonları kontrol eder
    IF @Durum=0 AND EXISTS (
        SELECT * FROM REZERVASYON
        WHERE MasaID=@MasaID AND Tarih>=CAST(GETDATE() AS DATE))
        BEGIN RAISERROR('Masaya ait ileri tarihli kayıt mevcuttur, önce iptal ediniz.', 16, 1); RETURN; END

    UPDATE MASA SET Aktif=@Durum WHERE MasaID=@MasaID;
END;
GO


CREATE PROCEDURE sp_MusteriGecmisi
    @MusteriID INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT r.RezID, r.Tarih, r.MasaID, r.KisiSayisi,
        CASE r.SaatDilimNo
            WHEN 1 THEN '09:00-12:00' WHEN 2 THEN '12:00-15:00'
            WHEN 3 THEN '15:00-18:00' WHEN 4 THEN '18:00-21:00'
            WHEN 5 THEN '21:00-00:00'
        END AS Saat
    FROM REZERVASYON r
    WHERE r.MusteriID=@MusteriID
    ORDER BY r.Tarih DESC;
END;
GO

CREATE PROCEDURE sp_AdminRezervasyonListesi 
AS
BEGIN
    SET NOCOUNT ON;
    SELECT 
        r.RezID,(m.Ad + ' ' + m.Soyad) AS Musteri,m.Telefon,r.MasaID,r.Tarih,
        CASE r.SaatDilimNo
            WHEN 1 THEN '09:00-12:00' WHEN 2 THEN '12:00-15:00'
            WHEN 3 THEN '15:00-18:00' WHEN 4 THEN '18:00-21:00' WHEN 5 THEN '21:00-00:00'
        END AS SaatDilimi,r.KisiSayisi,r.KaporaTutari
    FROM REZERVASYON r INNER JOIN MUSTERI m ON r.MusteriID = m.MusteriID
    ORDER BY r.Tarih DESC, r.SaatDilimNo ASC;
END;
GO


CREATE PROCEDURE sp_AdminRezervasyonSil
@RezID INT
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (SELECT * FROM REZERVASYON WHERE RezID = @RezID)
    BEGIN
        DELETE FROM REZERVASYON WHERE RezID = @RezID;
        SELECT 'Rezervasyon başarıyla silindi.' AS Mesaj;
    END
    ELSE
    BEGIN
        RAISERROR('Silinmek istenen kayıt bulunamadı!', 16, 1);
    END
END;
GO


-- TEST VERİLERİ 

INSERT INTO ADMIN_HESAP (KullaniciAdi, Sifre) 
VALUES ('admin', '********');
GO

INSERT INTO MASA (Kapasite, Aktif) VALUES 
(4,1),(4,1),(4,1),(4,1),(4,1),(4,1),
(4,1),(4,1),(4,1),(4,1),(4,1),(4,1);
GO


INSERT INTO MUSTERI (Ad, Soyad, KullaniciAdi, Telefon, Sifre) VALUES
('Ahmet',    'Yilmaz',  'ahmet01',   '05001112233', '********'),
('Mehmet',   'Kaya',    'mehmet_k',  '05001112234', '********'),
('Ayse',     'Demir',   'ayse_dmr',  '05001112235', '********'),
('Fatma',    'Celik',   'fatma_cl',  '05001112236', '********'),
('Emre',     'Arslan',  'emre_ars',  '05001112237', '********'),
('Zeynep',   'Koc',     'zeynep_k',  '05001112238', '********'),
('Burak',    'Sahin',   'burak_s',   '05001112239', '********'),
('Elif',     'Yildiz',  'elif_yldz', '05001112240', '********'),
('Can',      'Ozdemir', 'can_oz',    '05001112241', '********'),
('Selin',    'Aydin',   'selin_ayd', '05001112242', '********'),
('Murat',    'Dogan',   'murat_dg',  '05001112243', '********'),
('Hande',    'Polat',   'hande_p',   '05001112244', '********'),
('Tarik',    'Erdogan', 'tarik_e',   '05001112245', '********'),
('Gizem',    'Cetin',   'gizem_ct',  '05001112246', '********'),
('Serkan',   'Acar',    'serkan_a',  '05001112247', '********'),
('Busra',    'Kurt',    'busra_k',   '05001112248', '********'),
('Onur',     'Simsek',  'onur_s',    '05001112249', '********'),
('Neslihan', 'Gunes',   'nesli_g',   '05001112250', '********'),
('Cem',      'Bulut',   'cem_b',     '05001112251', '********'),
('Pinar',    'Yalcin',  'pinar_y',   '05001112252', '********');
GO

INSERT INTO REZERVASYON (MusteriID, MasaID, Tarih, SaatDilimNo, KisiSayisi, KaporaTutari) VALUES
(1,  1,  '2026-06-01', 1, 2, 150.00),
(2,  2,  '2026-06-01', 2, 3, 150.00),
(3,  3,  '2026-06-01', 3, 4, 150.00),
(4,  4,  '2026-06-01', 4, 2, 150.00),
(5,  5,  '2026-06-01', 5, 3, 150.00),
(6,  6,  '2026-06-02', 1, 2, 150.00),
(7,  7,  '2026-06-02', 2, 4, 150.00),
(8,  8,  '2026-06-02', 3, 1, 150.00),
(9,  9,  '2026-06-02', 4, 2, 150.00),
(10, 10, '2026-06-02', 5, 3, 150.00);
GO
