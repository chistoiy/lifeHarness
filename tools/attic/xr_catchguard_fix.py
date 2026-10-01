# tools/attic/xr_catchguard_fix.py — catch 必带日志守护整改：14 处静默吞噬补 AppLog / catch-ok
import io

CRLF = chr(13) + chr(10)


def patch(p, pairs):
    s = io.open(p, encoding='utf-8', newline='').read()
    crlf = CRLF in s

    def n(x):
        return x.replace(chr(10), CRLF) if crlf else x

    for a, b in pairs:
        a, b = n(a), n(b)
        assert s.count(a) == 1, (p, a[:50].encode('unicode_escape'), s.count(a))
        s = s.replace(a, b)
    io.open(p, 'w', encoding='utf-8', newline='').write(s)


# ---------- xray_scheduler：6 处 ----------
patch('lib/features/read/data/xray/xray_scheduler.dart', [
    ("import '../../../../core/database/schema/xray.dart' as xs;",
     "import '../../../../core/database/schema/xray.dart' as xs;\nimport '../../../../core/logging/app_log.dart';"),
    ("""      await dao.setBookMd5(book.id, m);
      return m;
    } catch (_) {
      return null;
    }""",
     """      await dao.setBookMd5(book.id, m);
      return m;
    } catch (e) {
      // 路径不可读/测试假路径＝返回 null 交 UI 空态；留痕便于真机排查懒补算失败。
      AppLog.add('指纹懒补算失败 书#${book.id}: $e', level: LhLevel.warn);
      return null;
    }"""),
    ("""      _pumpNext();
    } catch (e) {
      _onFail('$e');
    }
  }

  /// 喂下一章前的三道闸""",
     """      _pumpNext();
    } catch (e) {
      // catch-ok: 异常转交 _onFail——任务态 failed + live.error + 面板中断弹层，
      // 不是静默吞噬，是**上报路径本身**。
      _onFail('$e');
    }
  }

  /// 喂下一章前的三道闸"""),
    ("""      }
    } catch (e) {
      _inFlight = false;
      _onFail('$e');
    }""",
     """      }
    } catch (e) {
      // catch-ok: 同上——统一走 _onFail 落 failed 态并弹层报出。
      _inFlight = false;
      _onFail('$e');
    }"""),
    ("""          }
        } catch (e) {
          live.error = '$e';
        }""",
     """          }
        } catch (e) {
          // catch-ok: 补扫失败写进 live.error（面板头显示「上次失败」），非吞掉。
          live.error = '$e';
        }"""),
    ("""      } catch (e) {
        _onFail('$e');
      }
    }());
  }

  void _onFail(String message) {""",
     """      } catch (e) {
        // catch-ok: 落库链异常同样转 _onFail 上报（任务态 failed + 弹层）。
        _onFail('$e');
      }
    }());
  }

  void _onFail(String message) {"""),
    ("""        }
      } catch (_) {}
      _sched._bumpRevision();""",
     """        }
      } catch (_) {
        // catch-ok: failed 态写库自身失败无处可报（DB 已异常）；仍会 bump 刷新 UI。
      }
      _sched._bumpRevision();"""),
])

# ---------- open_with：5 处 ----------
patch('lib/features/read/presentation/open_with.dart', [
    ("""    return await _intentsChannel.invokeMethod<String>('takeEpubUri');
  } catch (_) {
    return null;
  }""",
     """    return await _intentsChannel.invokeMethod<String>('takeEpubUri');
  } catch (_) {
    // catch-ok: 原生侧未挂到 intents（非打开方式进入）＝无待接文件，属正常分支。
    return null;
  }"""),
    ("""    size = await brOpenFileSize(path);
  } catch (_) {}""",
     """    size = await brOpenFileSize(path);
  } catch (_) {
    // catch-ok: 体积仅展示位，取不到按 0 走（主链用路径直读，不依赖此值）。
  }"""),
    ("""    doc = await ref.read(epubDocLoaderProvider)(path);
  } on EpubFormatException catch (e) {
    if (context.mounted) readToast(context, e.reason);
    return;""",
     """    doc = await ref.read(epubDocLoaderProvider)(path);
  } on EpubFormatException catch (e) {
    // catch-ok: 坏包/DRM 是用户可解错误，已按原因 toast（页面级反馈即产物）。
    if (context.mounted) readToast(context, e.reason);
    return;"""),
    ("""  } catch (_) {
    if (context.mounted) readToast(context, '文件无法读取');
    return;""",
     """  } catch (_) {
    // catch-ok: 同上，读取异常的兜底文案已出toast；此处再落日志会与 loader 侧重复。
    if (context.mounted) readToast(context, '文件无法读取');
    return;"""),
    ("""    dup = await svc.findDup(doc);
  } catch (_) {
    dup = null;
  }""",
     """    dup = await svc.findDup(doc);
  } catch (e) {
    // catch-ok: 判重失败回落「按新建导入」是有意保守路径（宁重不丢）。
    dup = null;
    AppLog.add('打开方式判重查询失败: $e', level: LhLevel.warn);
  }"""),
])

# ---------- shelf_locate：1 处 ----------
patch('lib/features/read/presentation/shelf/shelf_locate.dart', [
    ("""      books = await ref.read(booksProvider.future);
    } catch (_) {
      books = const [];
    }""",
     """      books = await ref.read(booksProvider.future);
    } catch (_) {
      // catch-ok: 拉列表失败走「未在当前视图找到」兜底提示，用户可见、不静默。
      books = const [];
    }"""),
])

# ---------- reader_xray part：1 处 ----------
patch('lib/features/read/presentation/reader/reader_xray.dart', [
    ("""    ref.read(xraySchedulerProvider).noteBackground();
  } catch (_) {
    // 容器已销毁（页面出栈竞态）：调度器随 ProviderScope 存活，无需本页处理。
  }""",
     """    ref.read(xraySchedulerProvider).noteBackground();
  } catch (_) {
    // catch-ok: 容器已销毁（页面出栈竞态）——调度器随 ProviderScope 存活，无需本页处理。
  }"""),
])

# ---------- learn sheets：1 处（不可读包要留痕） ----------
patch('lib/features/read/presentation/reader/reader_xray_learn_sheets.dart', [
    ("""              } catch (e) {
                if (sc.mounted) readToast(sc, '包不可读：$e');
                return;
              }""",
     """              } catch (e) {
                // 导入包解析失败＝外部文件问题，留痕+toast 双出口。
                AppLog.add('.xraybak 解析失败: $e', level: LhLevel.error);
                if (sc.mounted) readToast(sc, '包不可读：$e');
                return;
              }"""),
])
print('catch guard remediation ok')
