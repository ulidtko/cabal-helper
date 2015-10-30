{-# LANGUAGE CPP #-}
module CabalHelper.Licenses where

-- Copyright (c) 2014, Jasper Van der Jeugt <m@jaspervdj.be>

--------------------------------------------------------------------------------
import Control.Arrow ((***), (&&&))
import Control.Monad (forM_, unless)
import Data.List (foldl', sort)
import Data.Maybe (catMaybes)
import Data.Version (Version)
import Data.Set (Set)
import qualified Data.Set as Set
import System.Directory (getDirectoryContents)
import System.Exit (exitFailure)
import System.FilePath (takeExtension)
import System.IO (hPutStrLn, stderr)

import Distribution.InstalledPackageInfo
import Distribution.InstalledPackageInfo
import Distribution.License
import Distribution.Package
import Distribution.Simple.Configure
import Distribution.Simple.LocalBuildInfo
import Distribution.Simple.PackageIndex
import Distribution.Text
--------------------------------------------------------------------------------

#if CABAL_MAJOR == 1 && CABAL_MINOR >  22
type CPackageIndex a = PackageIndex (InstalledPackageInfo)
#elif CABAL_MAJOR == 1 && CABAL_MINOR >= 22
type CPackageIndex a = PackageIndex (InstalledPackageInfo_ a)
#else
type CPackageIndex a = PackageIndex
#endif

#if CABAL_MAJOR == 1 && CABAL_MINOR > 22
type CInstalledPackageId = ComponentId
lookupInstalledPackageId = lookupComponentId
#endif



findTransitiveDependencies
    :: CPackageIndex a
    -> Set CInstalledPackageId
    -> Set CInstalledPackageId
findTransitiveDependencies pkgIdx set0 = go Set.empty (Set.toList set0)
  where
    go set []  = set
    go set (q : queue)
        | q `Set.member` set = go set queue
        | otherwise          =
            case lookupInstalledPackageId pkgIdx q of
                Nothing  ->
                    -- Not found can mean that the package still needs to be
                    -- installed (e.g. a component of the target cabal package).
                    -- We can ignore those.
                    go set queue
                Just ipi ->
                    go (Set.insert q set) (depends ipi ++ queue)


--------------------------------------------------------------------------------
getDependencyInstalledPackageIds
    :: LocalBuildInfo -> Set InstalledPackageId
getDependencyInstalledPackageIds lbi =
    findTransitiveDependencies (installedPkgs lbi) $
      Set.fromList $ map fst $ externalPackageDeps lbi

--------------------------------------------------------------------------------
getDependencyInstalledPackageInfos
    :: LocalBuildInfo -> [InstalledPackageInfo]
getDependencyInstalledPackageInfos lbi = catMaybes $
    map (lookupInstalledPackageId pkgIdx) $
    Set.toList (getDependencyInstalledPackageIds lbi)
  where
    pkgIdx = installedPkgs lbi


--------------------------------------------------------------------------------
groupByLicense
    :: [InstalledPackageInfo]
    -> [(License, [InstalledPackageInfo])]
groupByLicense = foldl'
    (\assoc ipi -> insert (license ipi) ipi assoc) []
  where
    -- 'Cabal.License' doesn't have an 'Ord' instance so we need to use an
    -- association list instead of 'Map'. The number of licenses probably won't
    -- exceed 100 so I think we're alright.
    insert :: Eq k => k -> v -> [(k, [v])] -> [(k, [v])]
    insert k v []   = [(k, [v])]
    insert k v ((k', vs) : kvs)
        | k == k'   = (k, v : vs) : kvs
        | otherwise = (k', vs) : insert k v kvs


--------------------------------------------------------------------------------
displayDependencyLicenseList
    :: [(License, [InstalledPackageInfo])]
    -> [(String, [(String, Version)])]
displayDependencyLicenseList =
    map (display *** map (getName &&& getVersion))
  where
    getName =
        display . pkgName . sourcePackageId
    getVersion =
        pkgVersion . sourcePackageId