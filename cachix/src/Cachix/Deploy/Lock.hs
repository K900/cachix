module Cachix.Deploy.Lock (withTryLock) where

import qualified Lukko as Lock
import Protolude hiding ((<.>))
import qualified System.Directory as Directory
import System.FilePath ((<.>), (</>))
import qualified System.Posix.Files as Files
import qualified System.Posix.Types as Posix

defaultLockDirectory :: FilePath
defaultLockDirectory = "cachix" </> "deploy" </> "locks"

-- | Get a path to the lock directory
getLockDirectoryFromProfile :: FilePath -> IO FilePath
getLockDirectoryFromProfile profile = do
  userId <- Files.fileOwner <$> Files.getFileStatus profile
  if isRoot userId
    then pure $ "/var/run" </> defaultLockDirectory
    else Directory.getXdgDirectory Directory.XdgCache defaultLockDirectory
  where
    isRoot :: Posix.UserID -> Bool
    isRoot = (==) 0

-- | Run an IO action with an acquired profile lock. Returns immediately if the profile is already locked.
--
-- Lock files are stored in either the user’s or system’s cache directory,
-- depending on the ownership of the profile.
--
-- Lock files are not deleted after use.
withTryLock :: FilePath -> IO a -> IO (Maybe a)
withTryLock path action = do
  lockDirectory <- getLockDirectoryFromProfile path

  Directory.createDirectoryIfMissing True lockDirectory
  Directory.setPermissions lockDirectory $
    Directory.emptyPermissions
      & Directory.setOwnerReadable True
      & Directory.setOwnerWritable True
      & Directory.setOwnerExecutable True
      & Directory.setOwnerSearchable True

  let lockFile = lockDirectory </> path <.> "lock"

  bracket
    (Lock.fdOpen lockFile)
    (Lock.fdUnlock *> Lock.fdClose)
    $ \fd -> do
      isLocked <- Lock.fdTryLock fd Lock.ExclusiveLock
      if isLocked
        then Just <$> action
        else pure Nothing